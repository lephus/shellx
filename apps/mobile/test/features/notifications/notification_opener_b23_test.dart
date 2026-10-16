import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/notification_opener.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fake_push.dart';
import '../../support/fakes.dart';

AiSessionInfo _info(String sid, {String? acp = 'sess-1', String cwd = '/p'}) => AiSessionInfo(
  sid: sid,
  agentId: 'claude',
  agentName: 'Claude',
  title: 'Nút đăng xuất',
  state: AiRemoteState.needsInput,
  cwd: cwd,
  acpSessionId: acp,
);

/// V2-2b B23, Review Focus 1: a push of a session of a previous run of ShellX on the computer opens the
/// session it is now, or the machine — and never answers anything.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late WorkspaceRegistry registry;
  late FakeMachineNavigator navigator;
  late NotificationOpener opener;

  setUp(() {
    backend = FakeBackend(devices: [agentDevice(agentA, 'MacBook Pro')], pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    final session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    navigator = FakeMachineNavigator();
    opener = NotificationOpener(session, registry, navigator);
  });

  tearDown(() => registry.dispose());

  PushMessage ai(String sid) => PushMessage(
    title: 'MacBook Pro · Claude',
    body: 'Cần bạn trả lời: Sửa src/main.ts',
    data: {'agent_id': agentA, 'kind': 'ai', 'ai_session': sid, 'perm': '41', 'allow': 'allow', 'reject': 'reject'},
  );

  /// The listing before ShellX restarted on the computer, then the one after.
  void restarted(List<AiSessionInfo> now) {
    machine.ai.emitListing(AiListing(sessions: [_info('e.-1')]));
    machine.ai.emitListing(AiListing(sessions: now));
  }

  void expectNothingAnswered() {
    expect(machine.ai.permissionAnswers, isEmpty);
    expect(machine.ai.askAnswers, isEmpty);
    expect(machine.ai.prompts, isEmpty);
  }

  test('a session the listing names opens as it is', () async {
    machine.ai.emitListing(AiListing(sessions: [_info('e.-1')]));
    await opener.open(ai('e.-1'));
    expect(navigator.shownAi, [(agentA, 'MacBook Pro', 'e.-1')]);
    expectNothingAnswered();
  });

  test('a session of the previous run opens as the one session of the same agent session now', () async {
    restarted([_info('k.-3'), _info('k.-4', acp: 'sess-2')]);
    await opener.open(ai('e.-1'));
    expect(navigator.shownAi, [(agentA, 'MacBook Pro', 'k.-3')]);
    expect(navigator.shown, isEmpty);
    expectNothingAnswered();
  });

  test('none, or two, of the same agent session now: the machine opens', () async {
    restarted([_info('k.-3', cwd: '/elsewhere')]);
    await opener.open(ai('e.-1'));
    restarted([_info('k.-3'), _info('k.-4')]);
    navigator.showing = null;
    await opener.open(ai('e.-1'));
    expect(navigator.shownAi, isEmpty);
    expect(navigator.shown, [(agentA, 'MacBook Pro'), (agentA, 'MacBook Pro')]);
    expectNothingAnswered();
  });

  test('a sid the phone never saw — a tab newer than the listing the phone holds — opens as it is', () async {
    machine.ai.emitListing(AiListing(sessions: [_info('k.-3')]));
    await opener.open(ai('k.-5'));
    expect(navigator.shownAi, [(agentA, 'MacBook Pro', 'k.-5')]);
    expect(navigator.shown, isEmpty);
    expectNothingAnswered();
  });

  test('a session seen without its agent session, no longer listed: the machine opens', () async {
    machine.ai.emitListing(AiListing(sessions: [_info('e.-1', acp: null)]));
    machine.ai.emitListing(AiListing(sessions: [_info('k.-3', acp: null)]));
    await opener.open(ai('e.-1'));
    expect(navigator.shownAi, isEmpty);
    expect(navigator.shown, [(agentA, 'MacBook Pro')]);
    expectNothingAnswered();
  });

  test('no listing held, or no window serving AI: nothing can tell, the session opens as before', () async {
    await opener.open(ai('e.-1'));
    machine.ai.emitListing(AiListing.unavailable);
    navigator.showingAi = null;
    await opener.open(ai('e.-1'));
    expect(navigator.shownAi, [(agentA, 'MacBook Pro', 'e.-1'), (agentA, 'MacBook Pro', 'e.-1')]);
    expectNothingAnswered();
  });
}
