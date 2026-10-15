import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

void main() {
  late InMemorySettingsStore settings;
  late ProviderContainer c;
  var next = 0;

  ProviderContainer boot() => ProviderContainer.test(
    overrides: [
      settingsStoreProvider.overrideWithValue(settings),
      toolIdSourceProvider.overrideWithValue(
        () => 'tool${(next++).toString().padLeft(6, '0')}',
      ),
    ],
  );

  ToolRegistry registry() => c.read(toolRegistryProvider.notifier);
  List<ToolEntry> tools() => c.read(toolRegistryProvider);
  List<Map<String, Object?>> stored() => [
    for (final s in settings.getStrings(SettingKeys.workspaceTools))
      jsonDecode(s) as Map<String, Object?>,
  ];

  setUp(() {
    next = 0;
    settings = InMemorySettingsStore();
    c = boot();
  });

  test('add normalises the URL, names a blank tool host:port, saves', () async {
    final t = registry().add(
      ws: 'default',
      name: '  ',
      url: ' localhost:5173 ',
    )!;
    expect(t.id, 'tool000000');
    expect(t.url, 'http://localhost:5173/');
    expect(t.name, 'localhost:5173');
    expect(tools(), [t]);
    await Future<void>.delayed(Duration.zero);
    expect(stored(), [t.toJson()]);
  });

  test('add refuses a bad URL and a full workspace (D2)', () {
    expect(
      registry().add(ws: 'default', name: 'x', url: 'javascript:alert(1)'),
      isNull,
    );
    expect(
      registry().add(ws: 'default', name: 'x', url: 'http://u:p@h/'),
      isNull,
    );
    expect(registry().add(ws: '', name: 'x', url: 'localhost:1'), isNull);
    for (var i = 0; i < kMaxToolsPerWorkspace; i++) {
      expect(
        registry().add(ws: 'w1', name: '$i', url: 'localhost:${i + 1}'),
        isNotNull,
      );
    }
    expect(
      registry().add(ws: 'w1', name: 'one more', url: 'localhost:9'),
      isNull,
    );
    expect(
      registry().add(ws: 'w2', name: 'elsewhere', url: 'localhost:9'),
      isNotNull,
    );
    expect(registry().inWorkspace('w1'), hasLength(kMaxToolsPerWorkspace));
  });

  test('the phone flag holds only for a tool a phone may open (D15)', () {
    final local = registry().add(
      ws: 'default',
      name: 'a',
      url: 'localhost:1',
      phone: true,
    )!;
    final secure = registry().add(
      ws: 'default',
      name: 'b',
      url: 'https://localhost:1',
      phone: true,
    )!;
    final remote = registry().add(
      ws: 'default',
      name: 'c',
      url: 'nas.lan:80',
      phone: true,
    )!;
    expect([local.phone, secure.phone, remote.phone], [true, false, false]);
  });

  test('update keeps the id, workspace and place; re-validates (D23)', () {
    final a = registry().add(ws: 'w1', name: 'A', url: 'localhost:1')!;
    final b = registry().add(ws: 'w1', name: 'B', url: 'localhost:2')!;
    registry().update(
      ToolEntry(
        id: a.id,
        ws: 'other',
        name: ' Bảng ',
        url: 'localhost:3#x',
        phone: true,
      ),
    );
    final moved = registry().byId(a.id)!;
    expect(
      [moved.ws, moved.name, moved.url, moved.phone],
      ['w1', 'Bảng', 'http://localhost:3/', true],
    );
    expect(tools().map((t) => t.id), [a.id, b.id]);
    registry().update(a.copyWith(url: 'file:///etc/passwd'));
    expect(registry().byId(a.id)!.url, 'http://localhost:3/');
    registry().update(a.copyWith(url: 'https://example.com', phone: true));
    expect(registry().byId(a.id)!.phone, isFalse);
    registry().update(
      ToolEntry(id: 'zzzzzzzzzz', ws: 'w1', name: 'n', url: 'localhost:1'),
    );
    expect(tools(), hasLength(2));
  });

  test('remove and removeWorkspace (D2, D23)', () {
    final a = registry().add(ws: 'w1', name: 'A', url: 'localhost:1')!;
    registry().add(ws: 'w2', name: 'B', url: 'localhost:2');
    registry().add(ws: 'w2', name: 'C', url: 'localhost:3');
    registry().remove(a.id);
    expect(registry().byId(a.id), isNull);
    registry().removeWorkspace('w2');
    expect(tools(), isEmpty);
    registry().remove('nope');
    registry().removeWorkspace('nope');
  });

  test('a restart reads back what was saved', () async {
    final a = registry().add(
      ws: 'w1',
      name: 'A',
      url: 'localhost:1',
      phone: true,
    )!;
    final b = registry().add(ws: 'w2', name: 'B', url: 'https://x.dev/app')!;
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    c = boot();
    expect(tools().map((t) => t.toJson()), [a.toJson(), b.toJson()]);
  });

  test(
    'a damaged, duplicate or extra entry goes; the others stay (§8)',
    () async {
      final good = ToolEntry(
        id: 'aaaaaaaaaa',
        ws: 'w1',
        name: 'A',
        url: 'http://localhost:1/',
      );
      await settings.setStrings(SettingKeys.workspaceTools, [
        '{not json',
        jsonEncode({'id': 'bad'}),
        jsonEncode(good.toJson()),
        jsonEncode(good.toJson()),
        for (var i = 0; i < kMaxToolsPerWorkspace + 2; i++)
          jsonEncode(
            ToolEntry(
              id: 'b${i.toString().padLeft(9, '0')}',
              ws: 'w2',
              name: 'n',
              url: 'http://localhost:${i + 1}/',
            ).toJson(),
          ),
      ]);
      c.dispose();
      c = boot();
      expect(registry().inWorkspace('w1').map((t) => t.id), ['aaaaaaaaaa']);
      expect(registry().inWorkspace('w2'), hasLength(kMaxToolsPerWorkspace));
    },
  );

  test('a failed save is not an error', () async {
    settings.fail = true;
    expect(registry().add(ws: 'w1', name: 'A', url: 'localhost:1'), isNotNull);
    await Future<void>.delayed(Duration.zero);
  });

  test('toString never shows a tool', () {
    registry().add(ws: 'w1', name: 'Secret', url: 'localhost:1');
    expect(registry().toString(), 'ToolRegistry(…)');
  });

  test('Review Focus 4: tools live in their own key; the workspace list an '
      'older build reads and rewrites is never touched (D2)', () async {
    await settings.setStrings(SettingKeys.terminalWorkspaces, [
      '{"id":"default","collapsed":false}',
    ]);
    final a = registry().add(ws: 'default', name: 'A', url: 'localhost:1')!;
    registry().update(a.copyWith(name: 'B'));
    registry().remove(a.id);
    await Future<void>.delayed(Duration.zero);
    expect(settings.getStrings(SettingKeys.terminalWorkspaces), [
      '{"id":"default","collapsed":false}',
    ]);
    expect(SettingKeys.all, contains(SettingKeys.workspaceTools));
    expect(UiSettingKeys.all, contains(SettingKeys.workspaceTools));
    expect(DaemonSettingKeys.all, isNot(contains(SettingKeys.workspaceTools)));
  });
}
