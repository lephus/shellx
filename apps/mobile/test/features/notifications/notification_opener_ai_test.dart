import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/notification_opener.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fake_push.dart';
import '../../support/fakes.dart';

/// V2-2 D11: an AI session's push opens that session.
void main() {
  late FakeBackend backend;
  late WorkspaceRegistry registry;
  late FakeMachineNavigator navigator;
  late NotificationOpener opener;

  setUp(() {
    backend = FakeBackend(devices: [agentDevice(agentA, 'MacBook Pro')], pinnedList: [pinned(agentA)]);
    backend.addMachine(agentA);
    final session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    navigator = FakeMachineNavigator();
    opener = NotificationOpener(session, registry, navigator);
  });

  tearDown(() => registry.dispose());

  PushMessage ai(String sid) => PushMessage(
    title: 'MacBook Pro · Claude',
    body: 'Cần bạn trả lời: Sửa src/main.ts',
    data: {'agent_id': agentA, 'kind': 'ai', 'ai_session': sid},
  );

  test('opens the AI session over the machine list', () async {
    await opener.open(ai('e.-1'));
    expect(navigator.shownAi, [(agentA, 'MacBook Pro', 'e.-1')]);
    expect(navigator.shown, isEmpty);
  });

  test('nothing when that session is already on top', () async {
    navigator.showingAi = '$agentA/e.-1';
    await opener.open(ai('e.-1'));
    expect(navigator.shownAi, isEmpty);
  });

  test('a push without ai_session opens the machine as before', () async {
    await opener.open(const PushMessage(title: 'MacBook Pro · Phiên 1', data: {'agent_id': agentA, 'kind': 'command'}));
    expect(navigator.shown, [(agentA, 'MacBook Pro')]);
    expect(navigator.shownAi, isEmpty);
  });
}
