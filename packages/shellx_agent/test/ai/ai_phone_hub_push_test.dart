import 'package:fake_async/fake_async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';
const tablet = 'b0000000-0000-4000-8000-000000000003';

PermissionRequest perm(String toolCallId) => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': toolCallId, 'title': 'Sửa src/main.ts'},
  'options': [
    {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ],
});

void say(AiSessionState s, String text) => s.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
  aiT0,
);

/// [who] acknowledges everything it was sent of session `ep.-1`.
void ackAll(HubRig rig, String who) {
  final seqs = [
    for (final m in rig.to(who))
      if (m is AiSnapshot && m.sid == 'ep.-1')
        m.seq
      else if (m is AiUpdate && m.sid == 'ep.-1')
        m.seq,
  ];
  if (seqs.isNotEmpty) rig.hub.handle(who, AiAck(sid: 'ep.-1', seq: seqs.last));
}

/// A hub whose clock is the fake one, with session `ep.-1` in a turn.
(HubRig, AiSessionState, List<AiPush>) running(FakeAsync async) {
  final pushes = <AiPush>[];
  final rig = HubRig(pushes: pushes, clock: () => aiT0.add(async.elapsed));
  final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
  return (rig, s, pushes);
}

/// V2-2 D11: a "needs you" push goes when nobody shows the request — on a
/// phone that mirrors the session (and is alive), or on the computer.
void main() {
  group('a phone that had the session open, and is gone (I2)', () {
    test('the request it showed is pushed when it goes, once', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(milliseconds: 150));
        ackAll(rig, phone);
        expect(pushes, isEmpty); // the phone shows it
        rig.hub.phoneGone(phone); // its channel dropped
        expect(pushes.single.kind, AiPushKind.needsInput);
        expect(pushes.single.detail, 'Sửa src/main.ts');
        say(s, 'more'); // the session goes on changing
        rig.hub.phoneGone(phone); // the router may say it twice
        rig.hub.allPhonesGone();
        async.elapse(const Duration(minutes: 5));
        expect(pushes, hasLength(1));
      });
    });

    test('the same when every phone goes at once (the relay link, the '
        'service link)', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.hub
          ..handle(phone, const AiAttach(sid: 'ep.-1'))
          ..handle(tablet, const AiAttach(sid: 'ep.-1'));
        s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(milliseconds: 150));
        ackAll(rig, phone);
        ackAll(rig, tablet);
        rig.hub.phoneGone(phone);
        expect(pushes, isEmpty); // the tablet still shows it
        rig.hub.allPhonesGone();
        expect(pushes, hasLength(1));
      });
    });

    test('one that never acknowledges the request does not count once its '
        '10 s are over: the push goes before the relay notices', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        ackAll(rig, phone); // alive until now …
        s.addPermission(perm('c1'), aiT0); // … and silent from here on
        async.elapse(const Duration(milliseconds: 9900));
        expect(pushes, isEmpty); // it may still take it
        async.elapse(const Duration(milliseconds: 200));
        expect(pushes.single.kind, AiPushKind.needsInput);
        rig.hub.phoneGone(phone); // the relay notices, minutes later
        async.elapse(const Duration(minutes: 5));
        expect(pushes, hasLength(1));
      });
    });

    test('one that attaches just before the 10 s end gets 10 s of its own '
        'to acknowledge the snapshot', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        s.addPermission(perm('c1'), aiT0); // the phone's socket is dead
        async.elapse(const Duration(milliseconds: 9900));
        rig.hub.handle(tablet, const AiAttach(sid: 'ep.-1'));
        async.elapse(const Duration(milliseconds: 300));
        expect(pushes, isEmpty);
        ackAll(rig, tablet);
        async.elapse(const Duration(minutes: 5));
        expect(pushes, isEmpty); // the tablet shows it
      });
    });

    test('one that acknowledged the request shows it: no push, a minute '
        'later neither', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(milliseconds: 150));
        ackAll(rig, phone);
        async.elapse(const Duration(minutes: 5));
        expect(pushes, isEmpty);
      });
    });

    test('one that attaches while a request waits shows it once it '
        'acknowledges the snapshot', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.source.seen.add(-1); // the computer shows it: no push at once
        s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(seconds: 20));
        rig.source.seen.clear();
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        ackAll(rig, phone);
        async.elapse(const Duration(minutes: 5));
        expect(pushes, isEmpty);
      });
    });

    test('the computer that shows the request: no push when the phone '
        'goes', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.source.seen.add(-1);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(milliseconds: 150));
        ackAll(rig, phone);
        rig.hub.phoneGone(phone);
        expect(pushes, isEmpty);
      });
    });

    test('one that only left the session page is not a silent one: no push '
        'when its 10 s end', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(milliseconds: 150));
        ackAll(rig, phone);
        rig.hub.handle(phone, const AiDetach(sid: 'ep.-1'));
        async.elapse(const Duration(seconds: 15));
        expect(pushes, isEmpty);
      });
    });

    test('a request answered meanwhile is not pushed', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        final p = s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(seconds: 5));
        s.resolvePermission(p.id, const PermissionSelected('allow'));
        async.elapse(const Duration(minutes: 5));
        rig.hub.phoneGone(phone);
        expect(pushes, isEmpty);
      });
    });
  });

  group('a minute after it came, whatever the computer shows (I4)', () {
    test('a request the computer shows: no push at 59 s, one at 60 s, '
        'never again', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.source.seen.add(-1); // focused window, focused pane
        s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(seconds: 59));
        expect(pushes, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(pushes.single.kind, AiPushKind.needsInput);
        expect(pushes.single.detail, 'Sửa src/main.ts');
        async.elapse(const Duration(minutes: 10));
        expect(pushes, hasLength(1));
      });
    });

    test('answered before its minute: no push', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.source.seen.add(-1);
        final p = s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(seconds: 59));
        s.resolvePermission(p.id, const PermissionSelected('allow'));
        async.elapse(const Duration(minutes: 10));
        expect(pushes, isEmpty);
      });
    });

    test('one the computer does not show is pushed at once, and not again '
        'at its minute', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        s.addPermission(perm('c1'), aiT0);
        expect(pushes, hasLength(1));
        async.elapse(const Duration(minutes: 10));
        expect(pushes, hasLength(1));
      });
    });

    test('the next request has a minute of its own', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.source.seen.add(-1);
        final p = s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(seconds: 50));
        s.resolvePermission(p.id, const PermissionSelected('allow'));
        s.addPermission(perm('c2'), aiT0);
        async.elapse(const Duration(seconds: 59));
        expect(pushes, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(pushes, hasLength(1));
      });
    });

    test('one a phone left on its page by itself: pushed when its minute is '
        'up, not when the phone leaves', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.source.seen.add(-1);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(milliseconds: 150));
        ackAll(rig, phone);
        async.elapse(const Duration(seconds: 20));
        rig.hub.handle(phone, const AiDetach(sid: 'ep.-1'));
        async.elapse(const Duration(seconds: 39));
        expect(pushes, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(pushes, hasLength(1));
      });
    });

    test('a phone that shows it goes after the minute: pushed then, the '
        'computer showing it or not', () {
      fakeAsync((async) {
        final (rig, s, pushes) = running(async);
        rig.source.seen.add(-1);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(milliseconds: 150));
        ackAll(rig, phone);
        async.elapse(const Duration(seconds: 90));
        expect(pushes, isEmpty); // the phone shows it
        rig.hub.phoneGone(phone);
        expect(pushes, hasLength(1));
      });
    });
  });
}
