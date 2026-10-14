import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/backend/backend.dart';

import '../../support/fakes.dart';

final _t0 = DateTime(2026, 10, 14, 9);

void _say(AiSessionState desktop, String text) => desktop.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
  _t0,
);

void _read(AiSessionState desktop, String id) => desktop.applyUpdate(
  SessionUpdate.fromJson({'sessionUpdate': 'tool_call', 'toolCallId': id, 'kind': 'read', 'title': 'Read $id'}),
  _t0,
);

/// The AI fakes act like `MachineAi` and its links (`shellx_client`) where the app's tests rely on
/// it: what a session holds comes through the real wire, a closed link is final, a lost channel
/// keeps the mirror, and requests fail the way the real ones do.
void main() {
  Matcher throwsRequest(String code) => throwsA(isA<AiRequestException>().having((e) => e.code, 'code', code));

  group('FakeAiSession', () {
    test('sync() brings what the computer holds, made by the real wire, and goes live', () {
      final ai = FakeAiSession('s1');
      var changes = 0;
      ai.changes.listen((_) => changes++);
      expect(ai.state, AiLinkState.attaching);
      expect(ai.mirror.head, isNull);

      ai.desktop.beginTurn(const [TextBlock('Thêm nút')], _t0);
      _say(ai.desktop, 'Xong **nút**.');
      ai.sync();

      expect(ai.state, AiLinkState.live);
      expect(changes, 1);
      expect(ai.mirror.head!.phase, 'running');
      expect(ai.mirror.head!.turn, isNotNull);
      expect(
        [for (final item in ai.mirror.items.cast<MirrorText>()) (item.kind, item.text)],
        [
          (MirrorTextKind.user, 'Thêm nút'),
          (MirrorTextKind.agent, 'Xong **nút**.'),
        ],
      );

      _say(ai.desktop, ' Thêm.');
      ai.sync();
      expect((ai.mirror.items.last as MirrorText).text, 'Xong **nút**. Thêm.');
      expect(changes, 2);
    });

    test('sync() brings a long answer whole, though the computer sends it in pieces', () {
      final ai = FakeAiSession('s1');
      final answer = '${'x' * 99999}!';
      _say(ai.desktop, answer);
      ai.sync();
      final text = ai.mirror.items.single as MirrorText;
      expect(text.text, answer);
      expect(text.rev, isNot(-1)); // -1: only a start of it is here
    });

    test('a re-attach is answered with a snapshot, though nothing changed meanwhile', () {
      final ai = FakeAiSession('s1');
      ai.desktop.beginTurn(const [TextBlock('go')], _t0);
      ai.sync();
      final before = ai.mirror.version;
      ai.lose();
      ai.sync();
      expect(ai.state, AiLinkState.live);
      expect(ai.mirror.version, greaterThan(before)); // the snapshot came: the header, at least
      expect(ai.mirror.changed, isEmpty); // none of the held items came again
      expect(ai.mirror.items, hasLength(1));
    });

    test('a lost channel keeps the mirror; the next sync attaches again with what it holds', () {
      final ai = FakeAiSession('s1');
      ai.desktop.beginTurn(const [TextBlock('go')], _t0);
      for (var i = 0; i < 5; i++) {
        _read(ai.desktop, 'c$i');
      }
      ai.sync();
      final held = ai.mirror.items;
      expect(held, hasLength(6));
      var changes = 0;
      ai.changes.listen((_) => changes++);

      ai.lose();
      expect(ai.state, AiLinkState.attaching);
      expect(changes, 1);
      expect(ai.mirror.items, held);
      ai.lose(); // nothing new to tell
      expect(changes, 1);

      _read(ai.desktop, 'c9');
      ai.sync();
      expect(ai.state, AiLinkState.live);
      expect(changes, 2);
      expect(ai.mirror.changed, {6}); // only the new card came again
      expect(ai.mirror.items.take(6).toList(), held);
    });

    test('a link that closed is final: it takes no more bodies and is not attaching again', () {
      final ai = FakeAiSession('s1')..sync();
      ai.close('desktop_closed');
      expect(ai.state, AiLinkState.closed);
      expect(ai.closedReason, 'desktop_closed');
      final version = ai.mirror.version;

      ai.desktop.beginTurn(const [TextBlock('go')], _t0);
      ai.sync();
      ai.lose();
      expect(ai.state, AiLinkState.closed);
      expect(ai.mirror.version, version);
      expect(ai.mirror.items, isEmpty);
    });

    test('detach() closes it like the real link: reason detached, one last change, the stream ends', () async {
      final ai = FakeAiSession('s1')..sync();
      final events = <String>[];
      ai.changes.listen((_) => events.add('change'), onDone: () => events.add('end'));

      ai.detach();
      await pumpEventQueue();
      expect(ai.detached, isTrue);
      expect(ai.state, AiLinkState.closed);
      expect(ai.closedReason, 'detached');
      expect(events, ['change', 'end']);

      // Nothing reaches a link that was detached.
      ai.sync();
      ai.lose();
      ai.close('gone');
      ai.loadEarlier();
      expect(ai.closedReason, 'detached');
      expect(events, ['change', 'end']);
    });

    test('detaching a link the computer closed keeps its reason', () async {
      final ai = FakeAiSession('s1')..sync();
      ai.close('gone');
      ai.detach();
      expect(ai.detached, isTrue);
      expect(ai.closedReason, 'gone');
    });

    test('a listener may detach from its own callback: it is told after the round, nothing fails', () async {
      final ai = FakeAiSession('s1');
      final seen = <AiLinkState>[];
      var ended = false;
      ai.changes.listen(
        (_) {
          seen.add(ai.state);
          if (ai.state == AiLinkState.live) ai.detach();
        },
        onDone: () => ended = true,
      );

      ai.sync();
      await pumpEventQueue();
      expect(seen, [AiLinkState.live, AiLinkState.closed]);
      expect(ai.closedReason, 'detached');
      expect(ended, isTrue);
    });

    test('loadEarlier() brings the page before the held window, once the link is live', () {
      final ai = FakeAiSession('s1');
      for (var i = 0; i < 100; i++) {
        _read(ai.desktop, 'c$i');
      }
      // A fresh attach brings the last kAiAttachItems; one page (kAiPageItems) is enough for the rest.
      const held = 100 - kAiAttachItems;
      expect(held, allOf(greaterThan(0), lessThanOrEqualTo(kAiPageItems)));
      ai.sync();
      expect(ai.mirror.from, held);
      expect(ai.mirror.hasEarlier, isTrue);

      ai.lose();
      ai.loadEarlier(); // the tap while reconnecting asks nothing of the computer
      expect((ai.earlierCalls, ai.mirror.from), (1, held));

      ai.sync();
      ai.loadEarlier();
      expect((ai.earlierCalls, ai.mirror.from), (2, 0));
      expect(ai.mirror.items, hasLength(100));
      expect(ai.mirror.hasEarlier, isFalse);

      ai.loadEarlier(); // nothing left
      expect((ai.earlierCalls, ai.mirror.from), (3, 0));
    });
  });

  group('FakeAiMachine', () {
    test('records every request', () async {
      final ai = FakeAiMachine();
      await ai.prompt('s1', 'hi');
      await ai.answerPermission('s1', 3, 'allow');
      await ai.answerAsk('s1', 4, const ElicitDecline());
      await ai.cancel('s1');
      await ai.forceStop('s1');
      await ai.unqueue('s1', 7);
      expect(await ai.open('claude', 'k1'), 'e.-9');
      ai.openedSid = 'e.5';
      expect(await ai.open('codex', 'k2'), 'e.5');
      await ai.watch();

      expect(ai.prompts, [('s1', 'hi')]);
      expect(ai.permissionAnswers, [('s1', 3, 'allow')]);
      expect(ai.askAnswers.single.$1, 's1');
      expect(ai.askAnswers.single.$2, 4);
      expect(ai.askAnswers.single.$3, isA<ElicitDecline>());
      expect(ai.cancels, ['s1']);
      expect(ai.forceStops, ['s1']);
      expect(ai.unqueued, [('s1', 7)]);
      expect(ai.opened, [('claude', 'k1'), ('codex', 'k2')]);
      expect(ai.watchCalls, 1);
    });

    test('failWith makes requests fail with that code, and a failed request is recorded too', () async {
      final ai = FakeAiMachine()..failWith = 'stale';
      await expectLater(ai.prompt('s1', 'again'), throwsRequest('stale'));
      await expectLater(ai.answerPermission('s1', 1, 'allow'), throwsRequest('stale'));
      await expectLater(ai.answerAsk('s1', 1, const ElicitCancel()), throwsRequest('stale'));
      await expectLater(ai.cancel('s1'), throwsRequest('stale'));
      await expectLater(ai.forceStop('s1'), throwsRequest('stale'));
      await expectLater(ai.unqueue('s1', 1), throwsRequest('stale'));
      await expectLater(ai.open('claude', 'k'), throwsRequest('stale'));
      expect(ai.prompts, [('s1', 'again')]);
      expect(ai.opened, [('claude', 'k')]);
      ai.failWith = null;
      await ai.prompt('s1', 'now');
    });

    test('connectFailure makes requests and watch() fail like a machine that cannot be reached', () async {
      final ai = FakeAiMachine()..connectFailure = MachineConnectionFailure.agentOffline;
      Matcher offline() => throwsA(
        isA<MachineConnectionException>().having((e) => e.failure, 'failure', MachineConnectionFailure.agentOffline),
      );
      await expectLater(ai.prompt('s1', 'hi'), offline());
      await expectLater(ai.cancel('s1'), offline());
      await expectLater(ai.open('claude', 'k'), offline());
      await expectLater(ai.watch(), offline());
      expect(ai.watchCalls, 1);
      // `attach` never throws: the real one connects in the background.
      expect(ai.attach('s1').state, AiLinkState.attaching);
    });

    test('gate holds a request in flight; what happens meanwhile decides how it ends', () async {
      final ai = FakeAiMachine()..gate = Completer<void>();
      var done = false;
      final pending = ai.answerPermission('s1', 3, 'allow');
      unawaited(pending.then((_) => done = true, onError: (Object _) => done = true));
      await pumpEventQueue();
      expect(ai.permissionAnswers, [('s1', 3, 'allow')]); // sent
      expect(done, isFalse); // not answered
      ai.failWith = 'unavailable'; // the window quit meanwhile
      ai.gate!.complete();
      await expectLater(pending, throwsRequest('unavailable'));
    });

    test('a listing says the computer has AI; "no window serves it" is a listing, not an error', () async {
      final ai = FakeAiMachine();
      expect(ai.supported, isNull);
      expect(ai.listing, isNull);
      final heard = <AiListing>[];
      ai.listings.listen(heard.add);

      ai.emitListing(AiListing.unavailable);
      expect(ai.supported, isTrue);
      expect(ai.listing!.available, isFalse);

      const session = AiSessionInfo(
        sid: 's1',
        agentId: 'claude',
        agentName: 'Claude',
        title: 'Thêm nút',
        state: AiRemoteState.needsInput,
      );
      ai.emitListing(const AiListing(sessions: [session]));
      expect(ai.listing!.available, isTrue);
      expect(ai.listing!.needsInput, 1);
      expect(heard, hasLength(2));
    });

    test('an old computer can be scripted: supported false, no listing', () {
      final ai = FakeAiMachine()..supportedValue = false;
      expect(ai.supported, isFalse);
      expect(ai.listing, isNull);
    });

    test('attach() is the same link while it is open, and a new one over the same session once it closed', () {
      final ai = FakeAiMachine();
      final first = ai.attach('s1') as FakeAiSession;
      expect(ai.attach('s1'), same(first));
      expect(ai.session('s1'), same(first));
      first.desktop.beginTurn(const [TextBlock('go')], _t0);
      first.sync();
      first.close('gone');

      final second = ai.attach('s1') as FakeAiSession;
      expect(second, isNot(same(first)));
      expect(second.state, AiLinkState.attaching);
      expect(second.mirror.items, isEmpty);
      expect(second.desktop, same(first.desktop));
      expect(ai.session('s1'), same(second));
      second.sync();
      expect(second.mirror.items, hasLength(1));
      expect(first.state, AiLinkState.closed);
      expect(first.closedReason, 'gone');
    });

    test('a test can set the session up before the page attaches', () {
      final ai = FakeAiMachine();
      ai.session('s1').desktop.beginTurn(const [TextBlock('go')], _t0);
      final link = ai.attach('s1') as FakeAiSession;
      link.sync();
      expect(link.mirror.items, hasLength(1));
    });
  });

  test('every fake machine session has its own AI machine', () {
    final a = FakeMachineSession(agentA);
    final b = FakeMachineSession(agentB);
    final MachineSession asPort = a;
    expect(asPort.ai, same(a.ai));
    expect(a.ai, isNot(same(b.ai)));
    expect(asPort.ai, isA<AiMachine>());
  });
}
