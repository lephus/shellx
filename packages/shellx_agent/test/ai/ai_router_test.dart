import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

/// Records every call; answers nothing.
final class _SpyEndpoint implements AiEndpoint {
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final handled = <(String, AiMessage)>[];
  final gone = <String>[];
  var allGone = 0;

  void say(String mobileId, AiMessage m) =>
      _out.add(OutboundMessage(mobileId, m));

  @override
  Stream<OutboundMessage> get outbound => _out.stream;
  @override
  void handle(String mobileId, AiMessage message) =>
      handled.add((mobileId, message));
  @override
  void phoneGone(String mobileId) => gone.add(mobileId);
  @override
  void allPhonesGone() => allGone++;
}

(SessionRouter, List<OutboundMessage>) _router({AiEndpoint? ai}) {
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

/// V2-2 D1, D3: the session router routes `ai.*`; the slot answers while
/// no window serves AI.
void main() {
  group('session router', () {
    test('ai: 1 only with an endpoint, only to a desktop: true list', () {
      fakeAsync((async) {
        final (withAi, sentA) = _router(ai: _SpyEndpoint());
        withAi.handle(phone, const SessionList(desktop: true));
        withAi.handle(phone, const SessionList());
        final (without, sentB) = _router();
        without.handle(phone, const SessionList(desktop: true));
        async.flushMicrotasks();
        final a = sentA.map((o) => o.message as SessionListResult).toList();
        expect(a.map((r) => r.ai), [kAiProtocol, null]);
        expect((sentB.single.message as SessionListResult).ai, isNull);
      });
    });

    test('ai.* goes to the endpoint, its answers to the phone; a phone '
        'leaving is told', () {
      final spy = _SpyEndpoint();
      final (router, sent) = _router(ai: spy);
      router.handle(phone, const AiList());
      spy.say(phone, const AiResult(rid: 1, ok: true));
      router.mobileDisconnected(phone);
      router.disconnectAllPhones();
      expect(spy.handled.single.$2, isA<AiList>());
      expect(sent.single.message, isA<AiResult>());
      expect(spy.gone, [phone]);
      expect(spy.allGone, 1);
    });

    test('without an endpoint ai.* is ignored, like an older agent', () {
      final (router, sent) = _router();
      router.handle(phone, const AiAttach(sid: 'x.1'));
      expect(sent, isEmpty);
    });
  });

  group('slot', () {
    test('answers unavailable until a hub is set, then forwards', () {
      final slot = AiEndpointSlot();
      final out = <OutboundMessage>[];
      slot.outbound.listen(out.add);
      slot.handle(phone, const AiList());
      slot.handle(phone, const AiAttach(sid: 'x.1'));
      slot.handle(phone, const AiPrompt(sid: 'x.1', rid: 4, text: 'hi'));
      slot.handle(phone, const AiAck(sid: 'x.1', seq: 1));
      expect(out.map((o) => o.message.type), [
        'ai.list.result',
        'ai.closed',
        'ai.result',
      ]);
      expect((out[0].message as AiListResult).available, isFalse);
      expect((out[2].message as AiResult).code, 'unavailable');
      final spy = _SpyEndpoint();
      slot.target = spy;
      slot.handle(phone, const AiList());
      spy.say(phone, const AiResult(rid: 9, ok: true));
      expect(spy.handled, hasLength(1));
      expect(out.last.message, const AiResult(rid: 9, ok: true));
    });
  });
}
