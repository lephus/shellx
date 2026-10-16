import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/closed_items.dart';
import 'package:shellx_desktop/src/terminal/focus_history.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;

  AgentEvent event(int pane, AgentEventKind kind) => AgentEvent(
    pane: pane,
    agent: AgentKind.claude,
    kind: kind,
    at: DateTime.now(),
  );

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    await c.read(terminalTabsProvider.notifier).openTab(); // tab 100
  });

  test('an AI pane takes A12 events while it is in its tab (D13)', () {
    final ai = openTestAiTab(c, select: false);
    final pane = ai.ai!.id;
    final status = c.read(agentStatusProvider.notifier);
    expect(status.ingest(event(pane, AgentEventKind.start)), isTrue);
    expect(status.ingest(event(pane, AgentEventKind.running)), isTrue);
    expect(c.read(agentStatusProvider)[pane]?.state, AgentState.running);
    expect(c.read(agentTabBadgeProvider(ai.id))?.state, AgentState.running);
    c.read(terminalTabsProvider.notifier).close(ai.id);
    expect(c.read(agentStatusProvider)[pane], isNull);
    expect(status.ingest(event(pane, AgentEventKind.running)), isFalse);
  });

  test('an AI pane stays running past the quiet decay (Review Focus 1)', () {
    fakeAsync((async) {
      final r = cliContainer(FakeLocalSessions());
      final ai = openTestAiTab(r);
      final status = r.read(agentStatusProvider.notifier);
      status.ingest(event(ai.ai!.id, AgentEventKind.start));
      status.ingest(event(ai.ai!.id, AgentEventKind.running));
      async.elapse(kAgentQuietDecay * 3);
      expect(r.read(agentStatusProvider)[ai.ai!.id]?.state, AgentState.running);
      r.dispose();
    });
  });

  test('a question in a hidden AI tab: one entry, one system notification '
      'titled by the tab, in the agent\'s own name (D13, B6)', () async {
    final ai = openTestAiTab(c, title: 'Fix login', select: false);
    final status = c.read(agentStatusProvider.notifier);
    status.ingest(event(ai.ai!.id, AgentEventKind.start));
    status.ingest(event(ai.ai!.id, AgentEventKind.needsInput));
    await pumpEventQueue();
    final entry = c.read(tabAttentionProvider).history.first;
    expect(entry.tabId, ai.id);
    expect(entry.paneId, ai.ai!.id);
    expect(entry.tabLabel, 'Fix login');
    expect(c.read(tabAttentionProvider).unread[ai.id]?.count, 1);
    final sent = systemNotificationsSent(c).single;
    expect(sent.title, 'Fix login');
    expect(sent.body, 'Claude needs your input');
    expect(local.notified, isEmpty, reason: 'no session carries it');
  });

  test('jumping to the notice selects the AI tab and its AI pane', () async {
    final ai = openTestAiTab(c, select: false);
    final status = c.read(agentStatusProvider.notifier);
    status.ingest(event(ai.ai!.id, AgentEventKind.start));
    status.ingest(event(ai.ai!.id, AgentEventKind.needsInput));
    await pumpEventQueue();
    expect(c.read(tabAttentionProvider.notifier).jumpTo(ai.id), isTrue);
    final tabs = c.read(terminalTabsProvider);
    expect(tabs.selectedId, ai.id);
    expect(tabs.selected!.focusedPaneId, ai.ai!.id);
    expect(c.read(tabAttentionProvider).unread[ai.id], isNull);
  });

  test('focus history goes back to an AI pane', () {
    final ai = openTestAiTab(c);
    final tabs = c.read(terminalTabsProvider.notifier);
    c.read(focusHistoryProvider);
    tabs.select(100);
    expect(c.read(focusHistoryProvider.notifier).go(back: true), isTrue);
    expect(c.read(terminalTabsProvider).selectedId, ai.id);
  });

  test('a closed AI tab is not offered back (B10)', () {
    final ai = openTestAiTab(c);
    c.read(closedItemsProvider);
    final before = c.read(closedItemsProvider).length;
    c.read(terminalTabsProvider.notifier).close(ai.id);
    expect(c.read(closedItemsProvider).length, before);
  });
}
