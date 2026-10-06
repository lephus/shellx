import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

void main() {
  late FakeLocalSessions local;

  setUp(() => local = FakeLocalSessions());

  test('pane notify goes through LocalSessions.notify; app notify is a '
      'command-line entry', () async {
    final c = cliContainer(local);
    await c.read(terminalTabsProvider.notifier).openTab();
    final h = c.read(uiCommandHandlerProvider);
    expect(h.notifyPane(100, title: 'CI', body: 'ok'), isTrue);
    expect(local.notified.single, (100, 'CI', 'ok'));
    expect(h.notifyPane(999, body: 'x'), isFalse);
    await pumpEventQueue();
    final sentBefore = systemNotificationsSent(c).length;
    await h.notifyApp(title: 'cron', body: 'backup done');
    final entry = c.read(tabAttentionProvider).history.first;
    expect(entry.tabId, kCommandLineTabId);
    expect(entry.paneId, kCommandLineTabId);
    expect(entry.tabLabel, 'Command line');
    expect(entry.read, isFalse);
    expect(c.read(tabAttentionProvider).unread.keys, isNot(contains(0)));
    final sent = systemNotificationsSent(c).skip(sentBefore).single;
    expect(sent.title, 'cron');
    expect(sent.body, 'backup done');
  });

  test('without a title the system notification says "Command line"', () async {
    final c = cliContainer(local);
    await c.read(uiCommandHandlerProvider).notifyApp(body: 'done');
    expect(systemNotificationsSent(c).single.title, 'Command line');
  });

  test('ui.notify (daemon → window, D34) is notifyApp; controls go, text is '
      'cut; blank text is bad_request', () async {
    final c = cliContainer(local);
    final h = c.read(uiCommandHandlerProvider);
    expect(
      await h.handle(
        MuxMessage(
          'ui.notify',
          q: 1,
          fields: {'title': 'cr\x1bon', 'body': 'a\x07b${'x' * 2000}'},
        ),
      ),
      isEmpty,
    );
    final n = c.read(tabAttentionProvider).history.first.notice;
    expect(n.title, 'cr on');
    expect(n.body, startsWith('a b'));
    expect(n.body!.length, 1024);
    await expectLater(
      h.handle(const MuxMessage('ui.notify', q: 2, fields: {'body': ' \n'})),
      throwsA(isA<CliFailure>().having((f) => f.code, 'code', 'bad_request')),
    );
  });

  test('ui.events.subscribe answers empty; events() streams the bus', () async {
    final c = cliContainer(local);
    final h = c.read(uiCommandHandlerProvider);
    expect(
      await h.handle(const MuxMessage('ui.events.subscribe', q: 1)),
      isEmpty,
    );
    final got = <Map<String, Object?>>[];
    h.events().listen(got.add);
    await c.read(terminalTabsProvider.notifier).openTab();
    await pumpEventQueue();
    expect(got.map((e) => e['kind']), contains('tab.opened'));
  });

  test('a command-line flood goes through the app limit (A4 D15)', () async {
    final c = cliContainer(local);
    final h = c.read(uiCommandHandlerProvider);
    for (var i = 0; i < 30; i++) {
      await h.notifyApp(body: 'n$i');
    }
    // One post, then the 3 s burst; never one per call.
    expect(systemNotificationsSent(c), hasLength(1));
    expect(c.read(tabAttentionProvider).history, hasLength(30));
  });
}
