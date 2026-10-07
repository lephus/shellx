import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';

import 'sidebar_test_harness.dart';

void main() {
  setUpSidebar();
  final devbox = SshTarget.parse('devbox')!;

  testSidebar('an SSH row: mark, remote ~, connecting dot, label (UI-A8 §2)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        cwd: '/home/me/work/api',
        remote: SessionRemote(
          launch: SshLaunch(devbox),
          connected: true,
          home: '/home/me',
        ),
      ),
    );
    local.add(
      local.summary(
        2,
        origin: SessionOrigin.desktop,
        remote: SessionRemote(launch: SshLaunch(devbox)),
      ),
    );
    await pumpSidebar(tester);
    expect(find.byKey(const Key('mark.remote.1')), findsOneWidget);
    expect(find.textContaining('~/work/api'), findsOneWidget);
    expect(
      find.descendant(
        of: row(2),
        matching: find.byKey(const Key('dot.connecting')),
      ),
      findsOneWidget,
    );
    expect(tester.getSemantics(row(1)).label, contains(', on devbox'));
    expect(tester.getSemantics(row(2)).label, contains('Connecting to devbox'));
    handle.dispose();
  });

  testSidebar('a server port link says it is forwarded over SSH', (
    tester,
  ) async {
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        cwd: '/home/me',
        ports: const [8000],
        remote: SessionRemote(
          launch: SshLaunch(devbox),
          connected: true,
          home: '/home/me',
        ),
      ),
    );
    await pumpSidebar(tester);
    expect(
      find.byTooltip('Open port 8000 on devbox (forwarded over SSH)'),
      findsOneWidget,
    );
  });

  testSidebar('an SSH workspace header shows the server icon', (tester) async {
    await pumpSidebar(tester);
    workspaces().createForHost(devbox);
    await tester.pump();
    expect(find.byIcon(Icons.dns_outlined), findsWidgets);
    expect(find.byTooltip('New SSH tab on devbox'), findsOneWidget);
  });

  SessionSummary sshTab(int id, {bool connected = true}) => local.summary(
    id,
    origin: SessionOrigin.desktop,
    remote: SessionRemote(launch: SshLaunch(devbox), connected: connected),
  );

  testSidebar('a server workspace menu: new server tab, new local tab, '
      'reconnect all (UI-A8 §2.3)', (tester) async {
    await pumpSidebar(tester);
    final id = workspaces().createForHost(devbox);
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('ws.$id')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.ws.newRemoteTab')), findsOneWidget);
    expect(find.byKey(const Key('menu.ws.newLocalTab')), findsOneWidget);
    final all = tester.widget<PopupMenuItem<Object?>>(
      find.byKey(const Key('menu.ws.reconnectAll')),
    );
    expect(all.enabled, isFalse);
    await tester.tap(find.byKey(const Key('menu.ws.newLocalTab')));
    await tester.pumpAndSettle();
    expect(tabs().tabs, hasLength(1));
    expect(tabs().tabs.single.focused.remote, isNull);
    expect(sidebar().tabsOf(id), [tabs().tabs.single.id]);
  });

  testSidebar('a local workspace menu has no server items', (tester) async {
    await pumpSidebar(tester);
    workspaces().createFor();
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('ws.default')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.ws.newRemoteTab')), findsNothing);
    expect(find.byKey(const Key('menu.ws.reconnectAll')), findsNothing);
  });

  testSidebar('a lost pane: the strip, and Reconnect first in the row menu', (
    tester,
  ) async {
    local.add(sshTab(1));
    await pumpSidebar(tester);
    expect(find.byKey(const Key('remote.strip.1')), findsNothing);
    local.summaries.clear();
    local.views[1]!.end(255);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('remote.strip.1')), findsOneWidget);
    await tester.tap(row(1), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.row.reconnect')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // Drop the reconnector's timer with the page.
  });

  testSidebar('losing the connection is announced once', (tester) async {
    final said = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final map = message as Map;
        if (map['type'] == 'announce') {
          said.add((map['data'] as Map)['message'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    local.add(sshTab(1));
    await pumpSidebar(tester);
    local.summaries.clear();
    local.views[1]!.end(255);
    await tester.pump();
    await tester.pump();
    expect(said.where((m) => m.contains('devbox')), [
      'Lost connection to devbox',
    ]);
  });
}
