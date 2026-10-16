import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';
import '../support/session_rig.dart' show phone, tablet;

// V2-2 D1, beyond `test/ai/ai_router_test.dart`: a revoked phone and a quit
// reach the endpoint, a disposed router lets go of it, the slot works behind
// a real router, and every answer of `aiUnavailableReply`.

/// Records every call; speaks to [phone] when a test says so.
final class _Spy implements AiEndpoint {
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final handled = <AiMessage>[];
  final gone = <String>[];
  var allGone = 0;

  void say(AiMessage m) => _out.add(OutboundMessage(phone, m));

  @override
  Stream<OutboundMessage> get outbound => _out.stream;
  @override
  void handle(String mobileId, AiMessage message) => handled.add(message);
  @override
  void phoneGone(String mobileId) => gone.add(mobileId);
  @override
  void allPhonesGone() => allGone++;
}

(SessionRouter, List<OutboundMessage>) _router(AiEndpoint ai) {
  var next = 10;
  int ids() => next++;
  final router = SessionRouter(
    shells: SessionManager(
      ptyFactory: FakePtyFactory(),
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
      nextId: ids,
    ),
    desktop: DesktopSessionManager(nextId: ids),
    desktopSharing: () => true,
    ai: ai,
  );
  final sent = <OutboundMessage>[];
  router.outbound.listen(sent.add);
  return (router, sent);
}

void main() {
  group('router and endpoint', () {
    test('a revoked phone and a quit are told to the endpoint', () {
      final spy = _Spy();
      final (router, _) = _router(spy);
      router.closeSessionsAttachedTo(tablet);
      router.closeAll();
      expect(spy.gone, [tablet]);
      expect(spy.allGone, 1);
    });

    test('a disposed router lets go of the endpoint', () {
      final spy = _Spy();
      final (router, sent) = _router(spy);
      spy.say(const AiResult(rid: 1, ok: true));
      router.dispose();
      spy.say(const AiResult(rid: 2, ok: true));
      expect(sent.map((o) => (o.message as AiResult).rid), [1]);
    });

    test('behind a router the slot says unavailable until a hub is set', () {
      final slot = AiEndpointSlot();
      final (router, sent) = _router(slot);
      router.handle(phone, const SessionList(desktop: true));
      router.handle(phone, const AiList());
      router.handle(phone, const AiAttach(sid: 'x.1'));
      expect(sent.map((o) => o.message.type), [
        'session.list.result',
        'ai.list.result',
        'ai.closed',
      ]);
      expect((sent.first.message as SessionListResult).ai, kAiProtocol);
      expect(sent.last.message.toMap(), {
        't': 'ai.closed',
        'sid': 'x.1',
        'reason': 'unavailable',
      });

      final spy = _Spy();
      slot.target = spy;
      sent.clear();
      router.handle(phone, const AiPrompt(sid: 'x.1', rid: 4, text: 'hi'));
      spy.say(const AiResult(rid: 4, ok: true));
      router.mobileDisconnected(phone);
      expect(spy.handled.map((m) => m.type), ['ai.prompt']);
      expect(sent.map((o) => o.message.type), ['ai.result']);
      expect(spy.gone, [phone]);
    });
  });

  group('slot', () {
    test('tells its target when phones go; with none, nobody is told', () {
      final slot = AiEndpointSlot();
      slot
        ..phoneGone(phone)
        ..allPhonesGone();
      final spy = _Spy();
      slot.target = spy;
      slot
        ..phoneGone(phone)
        ..allPhonesGone();
      expect(spy.gone, [phone]);
      expect(spy.allGone, 1);
    });

    test('a replaced or removed target no longer reaches the phones', () {
      final slot = AiEndpointSlot();
      final out = <OutboundMessage>[];
      slot.outbound.listen(out.add);
      final first = _Spy();
      final second = _Spy();
      slot.target = first;
      slot.target = second;
      first.say(const AiResult(rid: 1, ok: true));
      second.say(const AiResult(rid: 2, ok: true));
      slot.target = null;
      second.say(const AiResult(rid: 3, ok: true));
      slot.handle(phone, const AiList());
      expect(slot.target, isNull);
      expect(out.map((o) => o.message.type), ['ai.result', 'ai.list.result']);
      expect((out.first.message as AiResult).rid, 2);
    });
  });

  group('aiUnavailableReply', () {
    test('requests fail unavailable; the rest needs no answer; the reason '
        'is the caller\'s', () {
      const requests = <AiMessage>[
        AiPrompt(sid: 'x.1', rid: 11, text: 'hi'),
        AiAnswer(sid: 'x.1', rid: 12),
        AiCancel(sid: 'x.1', rid: 13),
        AiForceStop(sid: 'x.1', rid: 14),
        AiUnqueue(sid: 'x.1', rid: 15, queued: 1),
        AiOpen(rid: 16, agent: 'claude', folder: 'k'),
      ];
      for (final (i, request) in requests.indexed) {
        expect(aiUnavailableReply(request)?.toMap(), {
          't': 'ai.result',
          'rid': 11 + i,
          'ok': false,
          'code': 'unavailable',
        }, reason: request.type);
      }
      expect(aiUnavailableReply(const AiList())?.toMap(), {
        't': 'ai.list.result',
        'available': false,
        'body': emptyAiListingBody,
      });
      expect(
        aiUnavailableReply(
          const AiAttach(sid: 'x.1'),
          reason: 'desktop_closed',
        )?.toMap(),
        {'t': 'ai.closed', 'sid': 'x.1', 'reason': 'desktop_closed'},
      );
      // Nothing to answer; also the desktop → phone kinds a phone should
      // never send.
      const silent = <AiMessage>[
        AiDetach(sid: 'x.1'),
        AiAck(sid: 'x.1', seq: 1),
        AiEarlier(sid: 'x.1', before: 3),
        AiResult(rid: 1, ok: true),
        AiClosed(sid: 'x.1', reason: 'gone'),
      ];
      for (final message in silent) {
        expect(aiUnavailableReply(message), isNull, reason: message.type);
      }
    });
  });
}
