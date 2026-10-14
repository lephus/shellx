import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/notification_opener.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fake_push.dart';
import '../../support/fakes.dart';

/// V2-2 D11, the edges of an AI push: which machine, which session, and what opening it must never do.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late FakeMachineNavigator navigator;
  late NotificationOpener opener;

  setUp(() {
    backend = FakeBackend(devices: [agentDevice(agentA, 'MacBook Pro')], pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    navigator = FakeMachineNavigator();
    opener = NotificationOpener(session, registry, navigator);
  });

  tearDown(() => registry.dispose());

  PushMessage ai({
    String? agentId = agentA,
    String? sid = 'e.-1',
    String? sessionId,
    String title = 'MacBook Pro · Claude',
  }) => PushMessage(
    title: title,
    body: 'Cần bạn trả lời: Sửa src/main.ts',
    data: {'agent_id': ?agentId, 'kind': 'ai', 'ai_session': ?sid, 'session_id': ?sessionId},
  );

  group('PushMessage.aiSession', () {
    test('is the session the push is about; none when the key is missing or empty', () {
      expect(ai().aiSession, 'e.-1');
      expect(ai(sid: null).aiSession, isNull);
      expect(ai(sid: '').aiSession, isNull);
      expect(const PushMessage().aiSession, isNull);
    });

    test('is never printed: only the machine and the terminal session are', () {
      expect(ai().toString(), isNot(contains('e.-1')));
      expect(ai().toString(), isNot(contains('Sửa')));
    });
  });

  group('NotificationOpener', () {
    test('an empty ai_session is no AI session: the machine opens as it always did', () async {
      await opener.open(ai(sid: ''));
      expect(navigator.shown, [(agentA, 'MacBook Pro')]);
      expect(navigator.shownAi, isEmpty);
    });

    test('opens the session of the machine the push came from, not a machine that is not paired here', () async {
      await opener.open(ai(agentId: agentB));
      await opener.open(ai(agentId: null));
      expect(navigator.shownAi, isEmpty);
      expect(navigator.shown, isEmpty);
    });

    test('signed out, or a pinned-machines read that fails: nothing opens, nothing throws', () async {
      backend.pinnedError = Exception('keychain');
      await opener.open(ai());
      backend.pinnedError = null;
      session.signOut();
      await opener.open(ai());
      expect(navigator.shownAi, isEmpty);
    });

    test('the machine is named from GET /v1/devices, else from the title (`<machine> · <agent>`)', () async {
      await opener.open(ai());
      backend.devicesError = Exception('offline');
      await opener.open(ai(sid: 'e.-2'));
      expect(navigator.shownAi, [(agentA, 'MacBook Pro', 'e.-1'), (agentA, 'MacBook Pro', 'e.-2')]);

      navigator.showingAi = null;
      await opener.open(ai(sid: 'e.-3', title: 'Studio · Claude'));
      expect(navigator.shownAi.last, (agentA, 'Studio', 'e.-3'));
    });

    test('another session of the same machine opens too: only the same one is "already there"', () async {
      navigator.showingAi = '$agentA/e.-1';
      await opener.open(ai(sid: 'e.-2'));
      expect(navigator.shownAi, [(agentA, 'MacBook Pro', 'e.-2')]);
      // The same sid on another machine is another session.
      navigator.showingAi = '$agentB/e.-3';
      await opener.open(ai(sid: 'e.-3'));
      expect(navigator.shownAi.last, (agentA, 'MacBook Pro', 'e.-3'));
    });

    test('a push for a session that is already open does not even ask who the machine is', () {
      fakeAsync((async) {
        backend.devicesGate = Completer<void>(); // a lookup would wait here, up to its time-out
        navigator.showingAi = '$agentA/e.-1';
        var done = false;
        unawaited(opener.open(ai()).then((_) => done = true));
        async.flushMicrotasks();
        expect(done, isTrue, reason: 'no time passes');
        expect(navigator.shownAi, isEmpty);
      });
    });

    test('the same push twice while the machine is being named opens the session once', () async {
      final gate = backend.devicesGate = Completer<void>();
      final first = opener.open(ai());
      final second = opener.open(ai());
      await pumpEventQueue();
      expect(navigator.shownAi, isEmpty, reason: 'both are still asking who the machine is');
      gate.complete();
      await Future.wait([first, second]);
      expect(navigator.shownAi, [(agentA, 'MacBook Pro', 'e.-1')]);
    });

    test('signed out while the machine is being named: nothing opens', () async {
      final gate = backend.devicesGate = Completer<void>();
      final opening = opener.open(ai());
      await pumpEventQueue();
      session.signOut();
      gate.complete();
      await opening;
      expect(navigator.shownAi, isEmpty);
    });

    test('it shows the session and does nothing else: no tab selected, no answer, nothing sent', () async {
      await opener.open(ai(sessionId: '5'));
      expect(navigator.shownAi, [(agentA, 'MacBook Pro', 'e.-1')]);
      expect(navigator.shown, isEmpty, reason: 'the AI session wins over a terminal session id');
      expect(registry.forMachine(agentA).hasPendingSelect, isFalse);

      final ai0 = machine.ai;
      expect(ai0.permissionAnswers, isEmpty);
      expect(ai0.askAnswers, isEmpty);
      expect(ai0.prompts, isEmpty);
      expect(ai0.cancels, isEmpty);
      expect(ai0.forceStops, isEmpty);
      expect(ai0.unqueued, isEmpty);
      expect(ai0.opened, isEmpty);
      expect(ai0.sessions, isEmpty, reason: 'not even attached: the page does that');
    });
  });
}
