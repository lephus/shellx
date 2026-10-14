import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
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

AiListing listing(AiListResult r) =>
    AiListing.fromJson(decodeBody(r.body)!, available: r.available);

Uint8List json(Object v) => Uint8List.fromList(utf8.encode(jsonEncode(v)));

/// V2-2 D1, D2, D5, D10, D11: the window's side of AI on phones.
void main() {
  test('the body limit is the protocol limit', () {
    expect(kAiBodyBytes, kAiMaxBodyBytes);
  });

  group('listing', () {
    test('lists sessions with their state; resent only when it changed', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1, title: 'Fix cart');
        rig.source.add(-2, runs: false, unavailable: AiRemoteState.noFolder);
        rig.hub.handle(phone, const AiList());
        final first = listing(rig.last<AiListResult>(phone));
        expect(first.available, isTrue);
        expect(first.sessions.map((i) => (i.sid, i.state)), [
          ('ep.-1', AiRemoteState.idle),
          ('ep.-2', AiRemoteState.noFolder),
        ]);
        expect(first.folders.single.key, 'ws:a');

        s.beginTurn(const [TextBlock('go')], aiT0);
        for (var i = 0; i < 20; i++) {
          say(s, 'x');
        }
        async.elapse(const Duration(milliseconds: 300));
        final lists = rig.to(phone).whereType<AiListResult>().toList();
        expect(lists, hasLength(2)); // one coalesced change, not 21
        expect(listing(lists.last).sessions.first.state, AiRemoteState.running);
        async.elapse(const Duration(seconds: 1));
        expect(rig.to(phone).whereType<AiListResult>(), hasLength(2));
      });
    });
  });

  group('mirror', () {
    test('attach starts the agent and sends a snapshot; streaming is '
        'coalesced to one update per 100 ms', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        expect(rig.source.started, [-1]);
        expect(rig.to(phone).single, isA<AiSnapshot>());
        s.beginTurn(const [TextBlock('Viết hàm')], aiT0);
        async.flushTimers();
        final before = rig.to(phone).length;
        for (var i = 0; i < 50; i++) {
          say(s, 'chunk $i ');
          async.elapse(const Duration(milliseconds: 4)); // 200 ms in all
        }
        async.elapse(const Duration(milliseconds: 200));
        final updates = rig.to(phone).length - before;
        expect(updates, inInclusiveRange(2, 4));
        final mirror = rig.mirror(phone, 'ep.-1');
        expect((mirror.items.last as MirrorText).text, startsWith('chunk 0 '));
        expect((mirror.items.last as MirrorText).text, endsWith('chunk 49 '));
      });
    });

    test('the window stops updates until the phone acks', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        for (var i = 0; i < 40; i++) {
          say(s, '${'Dòng dài có dấu. ' * 800}\n');
          async.elapse(const Duration(milliseconds: 150));
        }
        final unacked = rig.to(phone).whereType<AiUpdate>().toList();
        final bytes = unacked.fold<int>(0, (n, u) => n + u.body.length);
        expect(bytes, lessThan(kAiWindowBytes + 2 * kAiBodyBytes));
        final count = unacked.length;
        rig.hub.handle(phone, AiAck(sid: 'ep.-1', seq: unacked.last.seq));
        async.elapse(const Duration(milliseconds: 150));
        expect(rig.to(phone).whereType<AiUpdate>().length, greaterThan(count));
      });
    });

    test('an unknown session, or one of another run, is closed', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-9'));
      rig.hub.handle(phone, const AiAttach(sid: 'old.-1'));
      expect(rig.to(phone).map((m) => (m as AiClosed).reason), [
        'gone',
        'gone',
      ]);
    });

    test('a session that cannot run says why', () {
      final rig = HubRig()
        ..source.add(-2, runs: false, unavailable: AiRemoteState.agentOff);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-2'));
      final m = rig.mirror(phone, 'ep.-2');
      expect(m.head!.unavailable, AiRemoteState.agentOff);
    });

    test('a tab that closes closes on the phone', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      rig.source.remove(-1);
      expect(rig.last<AiClosed>(phone).reason, 'gone');
    });
  });

  group('requests: explicit, checked against what is pending now (D10)', () {
    test('a prompt is sent; empty, too big or a full queue is refused', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1);
        final control = rig.source.controls[-1]!;
        rig.hub.handle(
          phone,
          const AiPrompt(sid: 'ep.-1', rid: 1, text: 'Sửa lỗi'),
        );
        rig.hub.handle(phone, const AiPrompt(sid: 'ep.-1', rid: 2, text: '  '));
        rig.hub.handle(
          phone,
          AiPrompt(
            sid: 'ep.-1',
            rid: 3,
            text: 'ắ' * (kAiMaxPromptBytes ~/ 3 + 1),
          ),
        );
        for (var i = 0; i < 6; i++) {
          rig.hub.handle(
            phone,
            AiPrompt(sid: 'ep.-1', rid: 10 + i, text: 'q$i'),
          );
        }
        async.flushMicrotasks();
        final results = {
          for (final r in rig.to(phone).whereType<AiResult>()) r.rid: r.code,
        };
        expect(results[1], isNull);
        expect(results[2], 'refused');
        expect(results[3], 'too_large');
        expect(results[15], 'queue_full');
        expect(control.sent.first, 'Sửa lỗi');
        expect(s.queue, hasLength(AiSessionState.maxQueue));
      });
    });

    test('a permission answer must name the pending request and one of its '
        'options; nothing is ever answered without one', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        final control = rig.source.controls[-1]!;
        rig.hub.handle(phone, const AiList());
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        final p = s.addPermission(perm('c1'), aiT0);
        async.elapse(const Duration(seconds: 5));
        expect(control.permissions, isEmpty); // never on its own
        rig.hub.handle(
          phone,
          AiAnswer(sid: 'ep.-1', rid: 1, permission: p.id + 7, option: 'allow'),
        );
        rig.hub.handle(
          phone,
          AiAnswer(sid: 'ep.-1', rid: 2, permission: p.id, option: 'yolo'),
        );
        rig.hub.handle(
          phone,
          AiAnswer(sid: 'ep.-1', rid: 3, permission: p.id, option: 'allow'),
        );
        rig.hub.handle(
          tablet,
          AiAnswer(sid: 'ep.-1', rid: 4, permission: p.id, option: 'reject'),
        );
        final codes = {
          for (final r in rig.sent.map((o) => o.message).whereType<AiResult>())
            r.rid: r.code,
        };
        expect(codes, {1: 'stale', 2: 'refused', 3: null, 4: 'stale'});
        expect(control.permissions, [(p.id, 'allow')]);
      });
    });

    test('a question: accept only with values the form accepts', () {
      final rig = HubRig();
      final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
      final control = rig.source.controls[-1]!;
      final a = s.addAsk(
        ElicitationRequest.fromJson({
          'mode': 'form',
          'message': 'Which?',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'pick': {
                'type': 'string',
                'enum': ['a', 'b'],
              },
            },
            'required': ['pick'],
          },
        }),
      )!;
      rig.hub.handle(
        phone,
        AiAnswer(
          sid: 'ep.-1',
          rid: 1,
          ask: a.id,
          action: 'accept',
          body: json({'pick': 'z'}),
        ),
      );
      rig.hub.handle(
        phone,
        AiAnswer(
          sid: 'ep.-1',
          rid: 2,
          ask: a.id,
          action: 'accept',
          body: json({'pick': 'b'}),
        ),
      );
      final codes = [
        for (final r in rig.to(phone).whereType<AiResult>()) r.code,
      ];
      expect(codes, ['refused', null]);
      expect((control.asks.single.$2 as ElicitAccept).content, {'pick': 'b'});
    });

    test('stop needs a turn; force stop only once the desktop offers it', () {
      final rig = HubRig();
      final s = rig.source.add(-1);
      final control = rig.source.controls[-1]!;
      rig.hub.handle(phone, const AiCancel(sid: 'ep.-1', rid: 1));
      s.beginTurn(const [TextBlock('go')], aiT0);
      rig.hub.handle(phone, const AiForceStop(sid: 'ep.-1', rid: 2));
      rig.hub.handle(phone, const AiCancel(sid: 'ep.-1', rid: 3));
      s.turn!.canForceStop = true;
      rig.hub.handle(phone, const AiForceStop(sid: 'ep.-1', rid: 4));
      final codes = [
        for (final r in rig.to(phone).whereType<AiResult>()) r.code,
      ];
      expect(codes, ['stale', 'refused', null, null]);
      expect((control.cancels, control.forceStops), (1, 1));
    });

    test('open answers the new session; a refused one says so', () async {
      final rig = HubRig();
      rig.source.opened = -5;
      rig.hub.handle(
        phone,
        const AiOpen(rid: 1, agent: 'claude', folder: 'ws:a'),
      );
      rig.source.opened = null;
      rig.hub.handle(
        phone,
        const AiOpen(rid: 2, agent: 'claude', folder: 'nope'),
      );
      await Future<void>.delayed(Duration.zero);
      final results = rig.to(phone).whereType<AiResult>().toList();
      expect((results[0].ok, results[0].sid), (true, 'ep.-5'));
      expect((results[1].ok, results[1].code), (false, 'refused'));
    });

    test('a phone that floods gets busy, then is heard again', () {
      fakeAsync((async) {
        final rig = HubRig()..source.add(-1);
        for (var i = 0; i < 100; i++) {
          rig.hub.handle(phone, AiCancel(sid: 'ep.-1', rid: i));
        }
        final busy = rig
            .to(phone)
            .whereType<AiResult>()
            .where((r) => r.code == 'busy');
        expect(busy.length, greaterThan(30));
        rig.now = rig.now.add(const Duration(seconds: 3));
        rig.hub.handle(phone, const AiCancel(sid: 'ep.-1', rid: 500));
        expect(rig.last<AiResult>(phone).code, 'stale');
      });
    });
  });

  group('push (D11)', () {
    test('needs-input pushes once per 30 s, only when no phone has the '
        'session open and the window does not show it', () {
      fakeAsync((async) {
        final pushes = <AiPush>[];
        final rig = HubRig(pushes: pushes);
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        final p1 = s.addPermission(perm('c1'), aiT0);
        expect(pushes.single.kind, AiPushKind.needsInput);
        expect(pushes.single.detail, 'Sửa src/main.ts');
        expect(pushes.single.sid, 'ep.-1');
        s.resolvePermission(p1.id, const PermissionSelected('allow'));
        s.addPermission(perm('c2'), aiT0);
        expect(pushes, hasLength(1)); // within 30 s
        rig.now = rig.now.add(const Duration(seconds: 31));
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        s.addPermission(perm('c3'), aiT0); // queued behind c2: no new one
        rig.hub.phoneGone(phone);
        rig.source.seen.add(-1);
        final p = s.permissions.first;
        s.resolvePermission(p.id, const PermissionSelected('allow'));
        expect(pushes, hasLength(1)); // seen on the computer
        rig.source.seen.clear();
        s.resolvePermission(
          s.permissions.first.id,
          const PermissionSelected('allow'),
        );
        s.addPermission(perm('c4'), aiT0);
        expect(pushes, hasLength(2));
      });
    });

    test('a phone that only lists still gets the push (shown in the app)', () {
      final pushes = <AiPush>[];
      final rig = HubRig(pushes: pushes);
      final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
      rig.hub.handle(phone, const AiList());
      s.addPermission(perm('c1'), aiT0);
      expect(pushes, hasLength(1));
    });

    test(
      'a long turn that ends pushes done; a short or stopped one does not',
      () {
        final pushes = <AiPush>[];
        final rig = HubRig(pushes: pushes);
        final s = rig.source.add(-1);
        s.beginTurn(const [TextBlock('a')], aiT0);
        s.endTurn(
          outcome: TurnOutcome.finished,
          at: aiT0.add(const Duration(seconds: 5)),
        );
        s.beginTurn(const [TextBlock('b')], aiT0);
        s.endTurn(
          outcome: TurnOutcome.cancelled,
          at: aiT0.add(const Duration(minutes: 5)),
        );
        s.beginTurn(const [TextBlock('c')], aiT0);
        s.endTurn(
          outcome: TurnOutcome.finished,
          at: aiT0.add(const Duration(minutes: 4)),
        );
        expect(pushes.map((p) => (p.kind, p.turn)), [(AiPushKind.done, 3)]);
        expect(pushes.single.elapsed, const Duration(minutes: 4));
      },
    );

    test('push fields round-trip for the background service', () {
      const push = AiPush(
        kind: AiPushKind.done,
        agentName: 'Claude',
        sid: 'ep.-1',
        turn: 3,
        elapsed: Duration(seconds: 61),
      );
      final back = AiPush.fromFields(push.toFields())!;
      expect(
        (back.kind, back.agentName, back.sid, back.turn, back.elapsed),
        (push.kind, push.agentName, push.sid, push.turn, push.elapsed),
      );
      expect('$push', '…');
    });
  });
}
