import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/cli_event_bus.dart';
import 'package:shellx_desktop/src/cli/cli_targets.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;

  Future<Map<String, Object?>> ls() => c
      .read(uiCommandHandlerProvider)
      .handle(const MuxMessage('ui.ls', q: 1, fields: {}));

  List<Map<String, Object?>> tabsOf(Map<String, Object?> ls) => [
    for (final t
        in ((ls['workspaces']! as List).single as Map)['tabs']! as List)
      t as Map<String, Object?>,
  ];

  Matcher notFound() => throwsA(
    isA<CliFailure>().having((e) => e.code, 'code', MuxError.notFound),
  );

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    await c.read(terminalTabsProvider.notifier).openTab(); // 100
  });

  test('ui.ls lists an AI tab: kind ai, title, cwd, no pane (D19)', () async {
    final ai = openTestAiTab(c, title: 'Fix login', cwd: '/w/shop');
    final got = await ls();
    final tabs = tabsOf(got);
    expect(tabs.first['kind'], 'terminal');
    final row = tabs.last;
    expect(row['id'], ai.id);
    expect(row['kind'], 'ai');
    expect(row['title'], 'Fix login');
    expect(row['cwd'], '/w/shop');
    expect(row['panes'], isEmpty);
    expect(got['selectedTab'], ai.id);
    expect(got['focusedPane'], isNull, reason: 'no terminal pane in focus');
  });

  test('an AI tab with a terminal pane lists it; targets reach it', () async {
    final ai = openTestAiTab(c);
    final term = await c
        .read(terminalTabsProvider.notifier)
        .addAiTerminal(ai.id);
    final row = tabsOf(await ls()).last;
    expect([for (final p in row['panes']! as List) (p as Map)['id']], [term]);
    c.read(terminalTabsProvider.notifier).focusPane(ai.ai!.id);
    final s = c.read(terminalTabsProvider);
    expect(resolvePane(s, TabRef(ai.id)), term);
    expect(resolvePane(s, const FocusedRef()), term);
  });

  test('a pane command on an AI tab without terminal is not_found', () {
    final ai = openTestAiTab(c);
    final s = c.read(terminalTabsProvider);
    expect(() => resolvePane(s, TabRef(ai.id)), notFound());
    expect(() => resolvePane(s, const FocusedRef()), notFound());
    expect(() => resolvePane(s, PaneRef(ai.ai!.id)), notFound());
    expect(resolveTab(s, TabRef(ai.id)), ai.id);
  });

  test('focusing the AI pane emits no pane.focused', () async {
    final got = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(got.add);
    final ai = openTestAiTab(c);
    final term = await c
        .read(terminalTabsProvider.notifier)
        .addAiTerminal(ai.id);
    await pumpEventQueue();
    got.clear();
    c.read(terminalTabsProvider.notifier).focusPane(ai.ai!.id);
    c.read(terminalTabsProvider.notifier).focusPane(term);
    await pumpEventQueue();
    final focused = [
      for (final e in got)
        if (e['kind'] == 'pane.focused') e['pane'],
    ];
    expect(focused, [term]);
  });
}
