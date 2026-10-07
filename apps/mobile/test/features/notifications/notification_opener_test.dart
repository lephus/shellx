import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/notification_opener.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

import '../../support/fake_push.dart';
import '../../support/fakes.dart';

PushMessage tapped({String? agentId = agentA, String? sessionId, String title = 'MacBook · Phiên 2'}) => PushMessage(
  title: title,
  body: '✓ make · 45 giây',
  data: {'agent_id': ?agentId, 'session_id': ?sessionId, 'kind': 'command'},
);

void main() {
  late FakeBackend backend;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late FakeMachineNavigator navigator;
  late NotificationOpener opener;

  setUp(() {
    backend = FakeBackend(devices: [agentDevice(agentA, 'MacBook Pro')], pinnedList: [pinned(agentA)]);
    backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    navigator = FakeMachineNavigator();
    opener = NotificationOpener(session, registry, navigator);
  });

  tearDown(() => registry.dispose());

  test('opens the machine of agent_id, named from GET /v1/devices', () async {
    await opener.open(tapped());
    expect(navigator.shown, [(agentA, 'MacBook Pro')]);
  });

  test('switches to the tab of session_id when it is open', () async {
    final workspace = registry.forMachine(agentA);
    final first = await workspace.openNew(fallbackGrid);
    final second = await workspace.openNew(fallbackGrid);
    workspace.select(0);

    await opener.open(tapped(sessionId: '${second.id}'));
    expect(workspace.activeTab.value, same(second));
    expect(navigator.shown, hasLength(1));

    // A session that is not a tab (ended, or never opened here): the machine opens as it is.
    await opener.open(tapped(sessionId: '999'));
    expect(workspace.activeTab.value, same(second));
    expect(first.id, isNot(999));
  });

  test(
    'the tab is not open yet (still reconnecting): the machine opens and the tab is selected when it appears',
    () async {
      final workspace = registry.forMachine(agentA);
      await workspace.openNew(fallbackGrid);

      await opener.open(tapped(sessionId: '777'));
      expect(workspace.hasPendingSelect, isTrue);
      expect(navigator.shown, [(agentA, 'MacBook Pro')]);

      await workspace.attach(
        const SessionInfo(id: 777, index: 3, shell: 'zsh', createdAt: 0, attached: false),
        fallbackGrid,
      );
      await workspace.openNew(fallbackGrid);
      expect(workspace.activeTab.value?.id, isNot(777), reason: 'a later tab opened by the user wins');
    },
  );

  test('already on that machine\'s page: only the tab changes', () async {
    final workspace = registry.forMachine(agentA);
    final first = await workspace.openNew(fallbackGrid);
    await workspace.openNew(fallbackGrid);
    navigator.showing = agentA;

    await opener.open(tapped(sessionId: '${first.id}'));
    expect(workspace.activeTab.value, same(first));
    expect(navigator.shown, isEmpty);
  });

  test('a machine not paired on this phone, no agent_id, or signed out: nothing opens', () async {
    await opener.open(tapped(agentId: agentB));
    await opener.open(tapped(agentId: null));
    session.signOut();
    await opener.open(tapped());
    expect(navigator.shown, isEmpty);
  });

  test('offline: the name comes from the title (`<machine> · …`)', () async {
    backend.devicesError = Exception('offline');
    await opener.open(tapped());
    expect(navigator.shown, [(agentA, 'MacBook')]);
  });

  test('a pinned-machines read that fails opens nothing and does not throw', () async {
    backend.pinnedError = Exception('keychain');
    await opener.open(tapped());
    expect(navigator.shown, isEmpty);
  });
}
