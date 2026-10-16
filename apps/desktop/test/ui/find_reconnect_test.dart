import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/find_sessions.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import 'sidebar_test_harness.dart';

void main() {
  setUpSidebar();

  testSidebar(
    'a reconnect keeps the find bar and its query on the pane (A8 D22)',
    (t) async {
      final devbox = SshTarget.parse('devbox')!;
      local.add(
        local.summary(
          1,
          origin: SessionOrigin.desktop,
          remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
        ),
      );
      await pumpSidebar(t);
      final terminal = tabs().tabs.first.panes[1]!.terminal;
      terminal.write('one error\r\ntwo error');
      final sessions = container.read(findSessionsProvider.notifier);
      final session = sessions.open(1)!;
      session.setQuery('error');
      await t.pump();
      expect(find.byKey(const Key('find.bar')), findsOneWidget);
      expect(session.matches, hasLength(2));

      local.summaries.removeWhere((s) => s.id == 1);
      local.views[1]!.end(255);
      await t.pump();
      await t.pump();
      final fresh = await t.runAsync(
        () => container.read(terminalTabsProvider.notifier).reconnect(1),
      );
      await t.pump();
      await t.pump();
      expect(fresh, isNotNull);

      final open = container.read(findSessionsProvider);
      expect(open.keys, [fresh]);
      expect(identical(open[fresh], session), isTrue);
      expect(session.query, 'error');
      expect(find.byKey(const Key('find.bar')), findsOneWidget);
      session.close();
    },
  );
}
