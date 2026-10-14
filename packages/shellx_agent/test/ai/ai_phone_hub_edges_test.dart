import 'dart:async';

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

void tool(AiSessionState s, String id) => s.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': 'tool_call',
    'toolCallId': id,
    'title': 'Read $id',
    'kind': 'read',
  }),
  aiT0,
);

AiListing listing(AiListResult r) =>
    AiListing.fromJson(decodeBody(r.body)!, available: r.available);

/// 81 items: an attach brings the last 60 and the phone can load 21 more.
AiSessionState longSession(HubRig rig) {
  final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
  for (var i = 0; i < 80; i++) {
    tool(s, 'c$i');
  }
  return s;
}

/// About 600 KB of text at 6 updates a second and not one ack: when this
/// returns, the window to the phone is full.
void fillWindow(FakeAsync async, AiSessionState s) {
  for (var i = 0; i < 40; i++) {
    say(s, '${'Dòng dài có dấu. ' * 800}\n');
    async.elapse(const Duration(milliseconds: 150));
  }
}

/// The phone acks everything it was sent of its latest attach.
void ackAll(HubRig rig, String who, String sid) {
  final last = [
    for (final m in rig.to(who))
      if (m is AiSnapshot) m.seq else if (m is AiUpdate) m.seq,
  ].last;
  rig.hub.handle(who, AiAck(sid: sid, seq: last));
}

bool isOlderPage(AiMessage m) =>
    m is AiUpdate && decodeBody(m.body)!['older'] == true;

/// V2-2 D5, D7, D11: the edges the main hub tests leave open — the window
/// gates every reply, no body passes the protocol limit, a phone that leaves
/// is forgotten once, a runtime that fails still answers once.
void main() {
  group('load earlier', () {
    test('a page of older items comes at once when the window has room', () {
      final rig = HubRig();
      longSession(rig);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      final held = rig.mirror(phone, 'ep.-1');
      expect((held.from, held.hasEarlier), (21, true));
      rig.hub.handle(phone, AiEarlier(sid: 'ep.-1', before: held.from));
      final mirror = rig.mirror(phone, 'ep.-1');
      expect((mirror.from, mirror.hasEarlier), (0, false));
      expect(rig.to(phone).whereType<AiUpdate>().single.seq, 2);
      // A page nobody asked for (another index) is not sent.
      rig.hub.handle(phone, const AiEarlier(sid: 'ep.-1', before: 7));
      expect(rig.to(phone).whereType<AiUpdate>(), hasLength(1));
    });

    test('with the window full a page waits for the phone to ack', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = longSession(rig);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        final from = rig.mirror(phone, 'ep.-1').from;
        fillWindow(async, s);
        final sent = rig.to(phone).length;
        rig.hub.handle(phone, AiEarlier(sid: 'ep.-1', before: from));
        async.elapse(const Duration(seconds: 1));
        expect(rig.to(phone).length, sent); // not one more byte
        expect(rig.mirror(phone, 'ep.-1').from, from);

        ackAll(rig, phone, 'ep.-1');
        expect(rig.mirror(phone, 'ep.-1').from, 0); // with the ack, at once
        async.elapse(const Duration(milliseconds: 150));
        expect(rig.to(phone).where(isOlderPage), hasLength(1));
      });
    });

    test('a page asked for twice while waiting is sent once', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = longSession(rig);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        final from = rig.mirror(phone, 'ep.-1').from;
        fillWindow(async, s);
        for (var i = 0; i < 3; i++) {
          rig.hub.handle(phone, AiEarlier(sid: 'ep.-1', before: from));
        }
        ackAll(rig, phone, 'ep.-1');
        async.elapse(const Duration(seconds: 1));
        expect(rig.to(phone).where(isOlderPage), hasLength(1));
      });
    });

    test('a page waiting is forgotten when the phone leaves the session', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = longSession(rig);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        final from = rig.mirror(phone, 'ep.-1').from;
        fillWindow(async, s);
        rig.hub.handle(phone, AiEarlier(sid: 'ep.-1', before: from));
        rig.hub.handle(phone, const AiDetach(sid: 'ep.-1'));
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        ackAll(rig, phone, 'ep.-1');
        async.elapse(const Duration(seconds: 1));
        expect(rig.to(phone).where(isOlderPage), isEmpty);
        // The fresh snapshot (one item newer) still has earlier items to load.
        expect(rig.mirror(phone, 'ep.-1').hasEarlier, isTrue);
        expect(rig.mirror(phone, 'ep.-1').from, greaterThanOrEqualTo(from));
      });
    });
  });

  group('no body passes the protocol limit', () {
    test('a session the codec cannot bound is closed, never sent', () {
      fakeAsync((async) {
        final rig = HubRig();
        // The agent's name is the desktop's own setting: the codec does not
        // clip it, so this header cannot fit one message.
        final s = AiSessionState(
          agentId: 'claude',
          agentName: 'C' * 70000,
          cwd: '/p',
        )..setPhase(AgentPhase.ready);
        rig.source.addState(-1, s);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        expect(rig.to(phone).map((m) => m.type), ['ai.closed']);
        expect(rig.last<AiClosed>(phone).reason, 'gone');
        s.beginTurn(const [TextBlock('go')], aiT0);
        async.elapse(const Duration(seconds: 1));
        expect(rig.to(phone), hasLength(1)); // it is not mirrored any more
      });
    });

    test('a listing too big for one message is cut from its end', () {
      final rig = HubRig();
      for (var i = 1; i <= 300; i++) {
        rig.source.add(-i, title: 'T$i ${'x' * 300}');
      }
      rig.hub.handle(phone, const AiList());
      final result = rig.last<AiListResult>(phone);
      expect(result.body.length, lessThanOrEqualTo(kAiRecordBytes));
      final l = listing(result);
      expect(l.sessions.length, allOf(greaterThan(50), lessThan(300)));
      expect(
        [for (final s in l.sessions) s.sid],
        [for (var i = 1; i <= l.sessions.length; i++) 'ep.-$i'],
      ); // the head of the list, in order
      expect(l.folders, isNotEmpty);
      expect(l.agents, isNotEmpty);
    });

    test('the longest part of a listing is the one that is cut', () {
      final rig = HubRig()
        ..source.add(-1)
        ..source.add(-2);
      rig.source.folders = [
        for (var i = 0; i < 600; i++)
          AiFolderChoice(
            key: 'path:/work/project-$i',
            name: 'project-$i',
            path: '/work/project-$i/${'sub/' * 30}',
          ),
      ];
      rig.hub.handle(phone, const AiList());
      final result = rig.last<AiListResult>(phone);
      expect(result.body.length, lessThanOrEqualTo(kAiRecordBytes));
      final l = listing(result);
      expect(l.sessions.map((s) => s.sid), ['ep.-1', 'ep.-2']); // all kept
      expect(l.folders.length, allOf(greaterThan(50), lessThan(600)));
      expect(l.folders.first.key, 'path:/work/project-0');
      expect(l.agents, isNotEmpty);
    });

    test('a listing nothing can cut down is sent empty, not too big', () {
      final rig = HubRig()..source.add(-1);
      rig.source.defaultAgent = 'x' * 70000; // an id: cut nowhere
      rig.hub.handle(phone, const AiList());
      final result = rig.last<AiListResult>(phone);
      expect(result.body.length, lessThan(100));
      expect(result.available, isTrue);
      expect(listing(result).sessions, isEmpty);
    });

    test('a session id too long to answer is not answered', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(phone, AiAttach(sid: 'x' * 70000));
      expect(rig.to(phone), isEmpty);
      rig.hub.handle(phone, const AiAttach(sid: 'old.-1'));
      expect(rig.last<AiClosed>(phone).sid, 'old.-1');
    });
  });

  group('phones that leave', () {
    test('a phone gone twice is forgotten once; nothing goes to it', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiList());
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        rig.hub.phoneGone(phone);
        rig.hub.phoneGone(phone); // the router may say it twice
        rig.hub.allPhonesGone();
        rig.hub.phoneGone(tablet); // never seen
        final sent = rig.sent.length;
        say(s, 'x');
        rig.source.add(-2);
        async.elapse(const Duration(seconds: 2));
        expect(rig.sent.length, sent);

        // On its next channel it starts over.
        rig.hub.handle(phone, const AiList());
        expect(listing(rig.last<AiListResult>(phone)).sessions, hasLength(2));
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        expect(rig.to(phone).whereType<AiSnapshot>(), hasLength(2));
      });
    });

    test('an answer that comes late is not sent to a phone that is gone', () {
      fakeAsync((async) {
        final rig = HubRig()..source.add(-1);
        final control = rig.source.controls[-1]!..hold = Completer<void>();
        rig.hub.handle(phone, const AiPrompt(sid: 'ep.-1', rid: 1, text: 'hi'));
        rig.hub.handle(
          tablet,
          const AiPrompt(sid: 'ep.-1', rid: 2, text: 'ho'),
        );
        rig.hub.phoneGone(phone);
        control.hold!.complete();
        async.flushMicrotasks();
        expect(rig.to(phone), isEmpty);
        expect(rig.last<AiResult>(tablet).rid, 2);
      });
    });

    test('dispose lets go of the window: no message, no push', () {
      fakeAsync((async) {
        final pushes = <AiPush>[];
        final rig = HubRig(pushes: pushes);
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiList());
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        async.flushTimers();
        rig.hub.dispose();
        final sent = rig.sent.length;
        say(s, 'x');
        s.addPermission(perm('c1'), aiT0);
        rig.source.add(-2);
        rig.hub.handle(phone, const AiList());
        async.elapse(const Duration(seconds: 2));
        expect(rig.sent.length, sent);
        expect(pushes, isEmpty);
      });
    });
  });

  group('requests', () {
    test('a session is named only the way the hub names it', () {
      final rig = HubRig()..source.add(1);
      for (final sid in ['ep.01', 'ep.+1', 'ep.0x1', 'ep. 1', 'ep.1 ']) {
        rig.hub.handle(phone, AiAttach(sid: sid));
      }
      expect(rig.to(phone).map((m) => m.type), List.filled(5, 'ai.closed'));
      rig.hub.handle(phone, const AiAttach(sid: 'ep.1'));
      expect(rig.to(phone).last, isA<AiSnapshot>());
    });

    test('a runtime that fails still answers once, and nothing is left '
        'unhandled', () async {
      final rig = HubRig();
      final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
      s.turn!.canForceStop = true;
      rig.source.controls[-1]!.failWith = StateError('boom');
      rig.hub.handle(phone, const AiPrompt(sid: 'ep.-1', rid: 1, text: 'hi'));
      rig.hub.handle(phone, const AiCancel(sid: 'ep.-1', rid: 2));
      rig.hub.handle(phone, const AiForceStop(sid: 'ep.-1', rid: 3));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final codes = {
        for (final r in rig.to(phone).whereType<AiResult>()) r.rid: r.code,
      };
      // The force stop was started; that it then failed is the window's.
      expect(codes, {1: 'refused', 2: 'refused', 3: null});
    });

    test('toString shows nothing a session holds', () {
      const entry = AiSessionEntry(
        paneId: -1,
        agentId: 'claude',
        agentName: 'Claude',
        title: 'secret title',
        cwd: '/secret/path',
      );
      expect('$entry', '…');
    });
  });

  group('mirror', () {
    test('a new runtime starts the phone over; the old state is let go', () {
      fakeAsync((async) {
        final rig = HubRig();
        final old = rig.source.add(-1);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        final first = decodeBody(rig.last<AiSnapshot>(phone).body)!;
        final fresh = rig.source.replace(-1);
        final snapshots = rig.to(phone).whereType<AiSnapshot>().toList();
        expect(snapshots, hasLength(2));
        final second = decodeBody(snapshots.last.body)!;
        expect(second['reset'], isTrue);
        expect(second['g'], isNot(first['g']));
        final sent = rig.sent.length;
        say(old, 'said by the old runtime');
        async.elapse(const Duration(seconds: 1));
        expect(rig.sent.length, sent); // nobody listens to it any more
        fresh.beginTurn(const [TextBlock('go')], aiT0);
        async.elapse(const Duration(seconds: 1));
        expect(rig.mirror(phone, 'ep.-1').head!.turn, isNotNull);
      });
    });

    test('two phones mirror one session, each at its own pace', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        rig.hub.handle(tablet, const AiAttach(sid: 'ep.-1'));
        for (var i = 0; i < 40; i++) {
          say(s, '${'Dòng dài có dấu. ' * 800}\n'); // only the tablet acks
          async.elapse(const Duration(milliseconds: 150));
          ackAll(rig, tablet, 'ep.-1');
        }
        String textOf(String who) =>
            (rig.mirror(who, 'ep.-1').items.last as MirrorText).text;
        final whole = (s.timeline.items.last as StreamedTextItem).text;
        expect(textOf(tablet), whole);
        expect(textOf(phone).length, lessThan(whole.length));
        for (var i = 0; i < 20 && textOf(phone) != whole; i++) {
          ackAll(rig, phone, 'ep.-1');
          async.elapse(const Duration(milliseconds: 150));
        }
        expect(textOf(phone), whole);
      });
    });
  });

  group('a clock set back', () {
    test('does not lock a phone out, nor stall the mirror', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        say(s, 'a');
        async.elapse(const Duration(milliseconds: 150)); // a flush, at aiT0
        rig.now = rig.now.subtract(const Duration(hours: 1));
        rig.hub.handle(phone, const AiCancel(sid: 'ep.-1', rid: 1));
        final result = rig.last<AiResult>(phone);
        expect((result.ok, result.code), (true, null)); // not busy
        say(s, 'b');
        async.elapse(const Duration(milliseconds: 150));
        final text = rig.mirror(phone, 'ep.-1').items.last as MirrorText;
        expect(text.text, endsWith('ab'));
      });
    });

    test('does not hide the next question', () {
      final pushes = <AiPush>[];
      final rig = HubRig(pushes: pushes);
      final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
      final p = s.addPermission(perm('c1'), aiT0);
      s.resolvePermission(p.id, const PermissionSelected('allow'));
      rig.now = rig.now.subtract(const Duration(hours: 1));
      s.addPermission(perm('c2'), aiT0);
      expect(pushes, hasLength(2));
    });
  });

  group('push (D11)', () {
    test('a done push does not use up the needs-input slot', () {
      final pushes = <AiPush>[];
      final rig = HubRig(pushes: pushes);
      final s = rig.source.add(-1);
      s.beginTurn(const [TextBlock('a')], aiT0);
      s.endTurn(
        outcome: TurnOutcome.finished,
        at: aiT0.add(const Duration(minutes: 4)),
      );
      rig.now = rig.now.add(const Duration(seconds: 10));
      s.beginTurn(const [TextBlock('b')], aiT0); // the queue goes on
      s.addPermission(perm('c1'), aiT0);
      expect(pushes.map((p) => p.kind), [
        AiPushKind.done,
        AiPushKind.needsInput,
      ]);
    });
  });
}
