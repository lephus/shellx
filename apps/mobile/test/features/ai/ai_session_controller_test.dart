import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';

import '../../support/fakes.dart';

const sid = 'e.-1';

const _permission = MirrorPermission(
  id: 7,
  title: 'Edit src/main.ts',
  options: [PermissionOption(optionId: 'allow', name: 'Yes', kind: PermissionKind.allowOnce)],
);

PermissionRequest _request() => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': 'c1', 'title': 'Edit src/main.ts', 'kind': 'edit'},
  'options': [
    {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ],
});

/// V2-2 §5.2 and D13: what the session page's controller asks of the computer, and what it says when
/// that fails.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
  });

  AiSessionController make() => AiSessionController(agentA, sid, session);

  group('the link', () {
    test('attaches when made and detaches on dispose, which is safe to repeat', () {
      final controller = make();
      final ai = machine.ai.session(sid);
      expect(ai.detached, isFalse);
      expect(controller.linkState, AiLinkState.attaching);
      controller
        ..dispose()
        ..dispose();
      expect(ai.detached, isTrue);
    });

    test('a closed link is detached too, so its mirror is let go', () {
      final controller = make();
      final ai = machine.ai.session(sid)..sync();
      ai.close('desktop_closed');
      expect(controller.closedReason, 'desktop_closed');
      controller.dispose();
      expect(ai.detached, isTrue);
    });

    test('another page of the same session that leaves does not close this one: a fresh link is taken', () {
      final first = make();
      final second = make(); // the same session: the client gives both the one link while it is open
      final shared = machine.ai.session(sid)..sync();
      expect(second.linkState, AiLinkState.live);
      first.dispose(); // detaches the link they share
      expect(shared.detached, isTrue);
      expect(second.linkState, AiLinkState.attaching);
      expect(second.closedReason, isNull);
      final fresh = machine.ai.session(sid);
      expect(identical(fresh, shared), isFalse);
      fresh.sync();
      expect(second.linkState, AiLinkState.live);
      second.dispose();
      expect(fresh.detached, isTrue);
    });

    test('every change of the link goes up the version; nothing after dispose', () {
      final controller = make();
      final ai = machine.ai.session(sid);
      final before = controller.version.value;
      ai.sync();
      expect(controller.version.value, greaterThan(before));
      final live = controller.version.value;
      ai.lose();
      expect(controller.version.value, greaterThan(live));
      controller.dispose();
      final last = controller.version.value;
      ai
        ..sync()
        ..close('gone');
      expect(controller.version.value, last);
    });

    test('the machine state follows the machine', () {
      final controller = make();
      expect(controller.machineState.value, isA<MachineIdle>());
      machine.emitState(const MachineFailed(MachineConnectionFailure.agentOffline));
      expect(controller.machineState.value, isA<MachineFailed>());
      controller.dispose();
      machine.emitState(const MachineReady());
      expect(controller.machineState.value, isA<MachineFailed>()); // not listening any more
    });

    test('a machine that is not pinned any more: closed, and the machine says why', () {
      backend.pinnedList = [];
      backend.machines.clear();
      final controller = make();
      expect(controller.closed.value, isTrue);
      expect(controller.mirror, isNull);
      expect(controller.linkState, AiLinkState.closed);
      final state = controller.machineState.value;
      expect(state, isA<MachineFailed>());
      expect((state as MachineFailed).failure, MachineConnectionFailure.untrusted);
      controller.dispose();
    });

    test('signed out: closed, nothing to show the relay state of', () async {
      final controller = AiSessionController(agentA, sid, FakeSessionHolder());
      expect(controller.closed.value, isTrue);
      expect(controller.backend, isNull);
      expect(await controller.send('hello'), 'refused');
      controller.dispose();
    });

    test('the clock ticks only while a turn runs, and not after dispose', () {
      fakeAsync((async) {
        final controller = make();
        final ai = machine.ai.session(sid);
        expect(async.periodicTimerCount, 0);
        ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
        ai.sync();
        expect(async.periodicTimerCount, 1);
        ai.desktop.endTurn(outcome: TurnOutcome.finished, at: DateTime.now());
        ai.sync();
        expect(async.periodicTimerCount, 0);
        ai.desktop.beginTurn(const [TextBlock('again')], DateTime.now());
        ai.sync();
        expect(async.periodicTimerCount, 1);
        controller.dispose();
        expect(async.periodicTimerCount, 0);
      });
    });

    test('"Tải thêm" asks the link', () {
      final controller = make();
      final ai = machine.ai.session(sid)..sync();
      controller.loadEarlier();
      expect(ai.earlierCalls, 1);
      controller.dispose();
    });
  });

  group('a request that the computer refuses says its code', () {
    test('every request, and success is null', () async {
      final controller = make();
      expect(await controller.send('a'), isNull);
      expect(await controller.answerPermission(_permission, _permission.options.single), isNull);
      expect(await controller.answerAsk(3, const ElicitDecline()), isNull);
      expect(await controller.stop(), isNull);
      expect(await controller.forceStop(), isNull);
      expect(await controller.unqueue(2), isNull);
      expect(machine.ai.prompts, [(sid, 'a')]);
      expect(machine.ai.permissionAnswers, [(sid, 7, 'allow')]);
      expect(machine.ai.cancels, [sid]);
      expect(machine.ai.forceStops, [sid]);
      expect(machine.ai.unqueued, [(sid, 2)]);
      controller.dispose();
    });

    for (final code in ['stale', 'queue_full', 'too_large', 'not_found', 'unavailable', 'a_newer_word']) {
      test('"$code"', () async {
        final controller = make();
        machine.ai.failWith = code;
        expect(await controller.send('a'), code);
        expect(await controller.answerPermission(_permission, _permission.options.single), code);
        expect(await controller.answerAsk(3, const ElicitDecline()), code);
        expect(await controller.stop(), code);
        expect(await controller.forceStop(), code);
        expect(await controller.unqueue(2), code);
        controller.dispose();
      });
    }

    test('nothing to send is refused before it travels', () async {
      final controller = make();
      expect(await controller.send('   '), 'refused');
      expect(machine.ai.prompts, isEmpty);
      controller.dispose();
    });
  });

  group('a request that could not reach the computer may have landed (D13)', () {
    // [agentOffline] and [timeout]: sent or not, nobody knows. [untrusted] and [protocolUnsupported]
    // are the handshake failing before anything is sent: the machine's own words.
    const outcomes = {
      MachineConnectionFailure.agentOffline: 'outcome_unknown',
      MachineConnectionFailure.timeout: 'outcome_unknown',
      MachineConnectionFailure.untrusted: 'untrusted',
      MachineConnectionFailure.protocolUnsupported: 'update_required',
    };
    for (final MapEntry(key: failure, value: code) in outcomes.entries) {
      test('${failure.name}: "$code", for every request, and nothing is sent again', () async {
        final controller = make();
        machine.ai.connectFailure = failure;
        expect(await controller.send('a'), code);
        expect(await controller.answerPermission(_permission, _permission.options.single), code);
        expect(await controller.answerAsk(3, const ElicitDecline()), code);
        expect(await controller.stop(), code);
        expect(await controller.forceStop(), code);
        expect(await controller.unqueue(2), code);
        // The computer is back: nothing goes by itself.
        machine.ai.connectFailure = null;
        machine.ai.session(sid)
          ..lose()
          ..sync();
        expect(machine.ai.prompts, [(sid, 'a')]);
        expect(machine.ai.permissionAnswers, hasLength(1));
        expect(machine.ai.askAnswers, hasLength(1));
        expect(machine.ai.cancels, hasLength(1));
        expect(machine.ai.forceStops, hasLength(1));
        expect(machine.ai.unqueued, hasLength(1));
        controller.dispose();
      });
    }

    test('anything else that goes wrong is a code too', () async {
      final controller = make();
      machine.ai.gate = Completer<void>();
      final sent = controller.send('a');
      machine.ai.gate!.completeError(StateError('contains the prompt text'));
      expect(await sent, 'error');
      expect(controller.sending.value, isFalse);
      controller.dispose();
    });
  });

  group('one answer at a time (V2-1 D10)', () {
    test('a second request of the kind is refused quietly while the first travels', () async {
      final controller = make();
      machine.ai.gate = Completer<void>();
      final first = controller.send('one');
      expect(controller.sending.value, isTrue);
      expect(await controller.send('two'), 'in_flight');
      machine.ai.gate!.complete();
      expect(await first, isNull);
      expect(controller.sending.value, isFalse);
      expect(machine.ai.prompts, [(sid, 'one')]);
      controller.dispose();
    });

    test('a stop already on its way is not asked again', () async {
      final controller = make();
      machine.ai.gate = Completer<void>();
      final first = controller.stop();
      expect(controller.stopping.value, isTrue);
      expect(await controller.stop(), 'in_flight');
      machine.ai.gate!.complete();
      expect(await first, isNull);
      expect(controller.stopping.value, isFalse);
      expect(machine.ai.cancels, [sid]);
      controller.dispose();
    });

    test('an answer waits for the computer to move on, not just for its own reply', () async {
      final controller = make();
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      final p = ai.desktop.addPermission(_request(), DateTime.now());
      ai.sync();
      final permission = controller.head!.permission!;
      expect(permission.id, p.id);

      expect(await controller.answerPermission(permission, permission.options.first), isNull);
      // The reply came; the header still shows the request: the buttons keep waiting.
      expect(controller.answering.value, p.id);
      expect(await controller.answerPermission(permission, permission.options.last), 'in_flight');
      expect(machine.ai.permissionAnswers, [(sid, p.id, 'allow')]);

      ai.desktop.resolvePermission(p.id, const PermissionSelected('allow'));
      ai.sync();
      expect(controller.answering.value, isNull);
      controller.dispose();
    });

    test('an answer whose header moved on before the reply does not wait', () async {
      final controller = make();
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      final p = ai.desktop.addPermission(_request(), DateTime.now());
      ai.sync();
      final permission = controller.head!.permission!;
      machine.ai.gate = Completer<void>();
      final answer = controller.answerPermission(permission, permission.options.first);
      ai.desktop.resolvePermission(p.id, const PermissionSelected('allow'));
      ai.sync(); // the update comes before the reply
      machine.ai.gate!.complete();
      expect(await answer, isNull);
      expect(controller.answering.value, isNull);
      controller.dispose();
    });

    test('a failed answer lets the buttons work again', () async {
      final controller = make();
      machine.ai.failWith = 'stale';
      expect(await controller.answerAsk(3, const ElicitDecline()), 'stale');
      expect(controller.answering.value, isNull);
      controller.dispose();
    });

    test('a lost connection lets a waiting answer go: what the computer shows now decides', () async {
      final controller = make();
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      ai.desktop.addPermission(_request(), DateTime.now());
      ai.sync();
      final permission = controller.head!.permission!;
      expect(await controller.answerPermission(permission, permission.options.first), isNull);
      expect(controller.answering.value, permission.id);
      ai.lose();
      expect(controller.answering.value, isNull);
      controller.dispose();
    });
  });
}
