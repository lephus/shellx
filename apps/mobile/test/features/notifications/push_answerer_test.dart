import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/notifications/domain/push_answer.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/push_answerer.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/fake_biometrics.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_push.dart';
import '../../support/fakes.dart';

const sid = 'k3f9za.-12';

PushMessage button(String action, {String perm = '41'}) => PushMessage(
  title: 'MacBook · Claude',
  body: 'Cần bạn trả lời: Sửa src/main.ts',
  data: {
    'kind': 'ai',
    'ai_session': sid,
    'agent_id': agentA,
    'perm': perm,
    'allow': 'allow-once',
    'reject': 'reject-once',
  },
  action: action,
);

/// V2-2b B10, Review Focus 1: one tap, one answer, after the app's lock; never another request, never twice.
void main() {
  late S s;
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late FakeBiometricAuthenticator biometrics;
  late bool lockEnabled;
  late AppLockController lock;
  late RecordingOpener opener;
  late FakePopupHandler popup;
  late PushAnswerer answerer;

  PushAnswerer build({
    Duration patience = const Duration(minutes: 2),
    Duration relayWait = const Duration(seconds: 10),
  }) => PushAnswerer(
    session: session,
    lock: lock,
    opener: opener,
    popup: () => popup,
    words: () => s,
    patience: patience,
    relayWait: relayWait,
  );

  setUp(() async {
    s = await S.load(const Locale('vi'));
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    biometrics = FakeBiometricAuthenticator();
    lockEnabled = false;
    lock = AppLockController(authenticator: biometrics, isEnabled: () => lockEnabled);
    opener = RecordingOpener();
    popup = FakePopupHandler();
    answerer = build();
  });

  Future<void> answer(PushMessage message) => answerer.answer(message, PushAnswer.of(message)!);

  test('"Cho phép": one answer with the allow option, then the session opens and says what was allowed', () async {
    final message = button('allow');
    await answer(message);
    expect(machine.ai.permissionAnswers, [(sid, 41, 'allow-once')]);
    expect(opener.opened, [message]);
    expect(popup.successes, ['Đã cho phép: Sửa src/main.ts']);
  });

  test('"Từ chối": the reject option', () async {
    await answer(button('reject'));
    expect(machine.ai.permissionAnswers, [(sid, 41, 'reject-once')]);
    expect(popup.successes, ['Đã từ chối: Sửa src/main.ts']);
  });

  test('the app is locked: nothing goes before Face ID; it goes once the lock opens', () async {
    lockEnabled = true;
    lock.lockOnLaunch();
    final done = answer(button('allow'));
    await pumpEventQueue();
    expect(machine.ai.permissionAnswers, isEmpty);
    expect(await lock.unlock('Mở khóa ShellX'), isTrue);
    await done;
    expect(machine.ai.permissionAnswers, hasLength(1));
  });

  test('a cancelled unlock sends nothing, also when the app is unlocked later', () async {
    lockEnabled = true;
    lock.lockOnLaunch();
    biometrics.result = false;
    final done = answer(button('allow'));
    expect(await lock.unlock('Mở khóa ShellX'), isFalse);
    await done;
    biometrics.result = true;
    expect(await lock.unlock('Mở khóa ShellX'), isTrue);
    await pumpEventQueue();
    expect(machine.ai.permissionAnswers, isEmpty);
    expect(opener.opened, isEmpty);
  });

  test('the app leaves the foreground before the answer went: nothing is sent', () async {
    lockEnabled = true;
    lock.lockOnLaunch();
    final done = answer(button('allow'));
    lock.onBackgrounded();
    await done;
    lock.onForegrounded();
    await lock.unlock('Mở khóa ShellX');
    await pumpEventQueue();
    expect(machine.ai.permissionAnswers, isEmpty);
  });

  test('a button that arrives before the app is back in the foreground waits for it', () async {
    lock.onBackgrounded();
    final done = answer(button('allow'));
    await pumpEventQueue();
    expect(machine.ai.permissionAnswers, isEmpty);
    lock.onForegrounded();
    await done;
    expect(machine.ai.permissionAnswers, hasLength(1));
  });

  test('no unlock within its patience: dropped', () async {
    lockEnabled = true;
    lock.lockOnLaunch();
    answerer = build(patience: const Duration(milliseconds: 20));
    await answer(button('allow'));
    await lock.unlock('Mở khóa ShellX');
    await pumpEventQueue();
    expect(machine.ai.permissionAnswers, isEmpty);
  });

  test('stale says it was answered elsewhere and sends nothing else', () async {
    machine.ai.failWith = 'stale';
    await answer(button('allow'));
    expect(machine.ai.permissionAnswers, hasLength(1));
    expect(popup.infos, ['Yêu cầu này đã được trả lời ở nơi khác.']);
    expect(popup.successes, isEmpty);
  });

  test('an old sid gets not_found, then the page: a push of the run before a restart says the session closed, then '
      'the session opens (B23 finds it again when it can); nothing else is answered', () async {
    machine.ai.failWith = 'not_found';
    final message = button('allow');
    await answer(message);
    expect(machine.ai.permissionAnswers, hasLength(1));
    expect(popup.infos, ['Phiên AI này đã đóng trên máy tính.']);
    expect(opener.opened, [message]);
  });

  test('on_computer: "Trả lời yêu cầu này trên máy tính."; no window: "Mở ShellX trên máy tính…"', () async {
    machine.ai.failWith = 'on_computer';
    await answer(button('allow', perm: '1'));
    machine.ai.failWith = 'unavailable';
    await answer(button('allow', perm: '2'));
    expect(popup.infos, ['Trả lời yêu cầu này trên máy tính.', 'Mở ShellX trên máy tính để dùng phiên AI.']);
  });

  test('a lost channel is never retried ("Có thể chưa gửi được. Xem trong phiên.")', () async {
    machine.ai.connectFailure = MachineConnectionFailure.agentOffline;
    final message = button('allow');
    await answer(message);
    expect(popup.errors, ['Có thể chưa gửi được. Xem trong phiên.']);
    machine.ai.connectFailure = null;
    // The same button again (a launch, then a resume): answered once.
    await answer(message);
    expect(machine.ai.permissionAnswers, hasLength(1));
  });

  test('the computer cannot be reached before anything went: its words, nothing sent', () async {
    machine.connectFailure = MachineConnectionFailure.agentOffline;
    await answer(button('allow'));
    expect(machine.ai.permissionAnswers, isEmpty);
    expect(popup.errors, [s.errorAgentOffline]);
  });

  test('a launch from the push: the answer waits for the relay', () async {
    backend.relayStateValue = RelayConnectionState.connecting;
    final done = answer(button('allow'));
    await pumpEventQueue();
    expect(machine.ai.permissionAnswers, isEmpty);
    backend.emitRelay(RelayConnectionState.connected);
    await done;
    expect(machine.ai.permissionAnswers, hasLength(1));
  });

  test('the relay never comes: nothing sent, "the computer did not answer"', () async {
    backend.relayStateValue = RelayConnectionState.connecting;
    answerer = build(relayWait: const Duration(milliseconds: 20));
    await answer(button('allow'));
    expect(machine.ai.permissionAnswers, isEmpty);
    expect(popup.errors, [s.errorTimeout]);
  });

  test('a machine not paired on this phone (another account\'s): nothing is sent or opened', () async {
    backend.pinnedList = [];
    await answer(button('allow'));
    expect(machine.ai.permissionAnswers, isEmpty);
    expect(opener.opened, isEmpty);
    expect(popup.errors, isEmpty);
  });

  test('signed out: nothing', () async {
    session.signOut();
    await answer(button('allow'));
    expect(machine.ai.permissionAnswers, isEmpty);
  });
}
