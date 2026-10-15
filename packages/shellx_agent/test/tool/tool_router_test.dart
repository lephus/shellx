import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

/// Records every call; answers nothing.
final class _SpyEndpoint implements ToolEndpoint {
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final handled = <(String, ToolMessage)>[];
  final gone = <String>[];
  var allGone = 0;

  @override
  bool serving = true;

  void say(String mobileId, ToolMessage m) =>
      _out.add(OutboundMessage(mobileId, m));

  @override
  Stream<OutboundMessage> get outbound => _out.stream;
  @override
  void handle(String mobileId, ToolMessage message) =>
      handled.add((mobileId, message));
  @override
  void phoneGone(String mobileId) => gone.add(mobileId);
  @override
  void allPhonesGone() => allGone++;
}

(SessionRouter, List<OutboundMessage>) _router({ToolEndpoint? tools}) {
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
    tools: tools,
  );
  final sent = <OutboundMessage>[];
  router.outbound.listen(sent.add);
  return (router, sent);
}

/// V2-4 E5, E6: the session router routes `tool.*`; the slot answers while
/// no proxy serves.
void main() {
  group('session router', () {
    test('tools: 1 only while an endpoint serves, only to a desktop: true '
        'list', () {
      fakeAsync((async) {
        final spy = _SpyEndpoint();
        final (withTools, sentA) = _router(tools: spy);
        withTools.handle(phone, const SessionList(desktop: true));
        withTools.handle(phone, const SessionList());
        spy.serving = false;
        withTools.handle(phone, const SessionList(desktop: true));
        final (without, sentB) = _router();
        without.handle(phone, const SessionList(desktop: true));
        async.flushMicrotasks();
        final a = sentA.map((o) => o.message as SessionListResult).toList();
        expect(a.map((r) => r.tools), [kToolProtocol, null, null]);
        expect((sentB.single.message as SessionListResult).tools, isNull);
      });
    });

    test('tool.* goes to the endpoint, its answers to the phone; a phone '
        'leaving, a revoke and a stop are told', () {
      final spy = _SpyEndpoint();
      final (router, sent) = _router(tools: spy);
      router.handle(phone, const ToolList());
      spy.say(phone, const ToolEnd(id: 1, code: 'aborted'));
      router.mobileDisconnected(phone);
      router.closeSessionsAttachedTo(phone);
      router.disconnectAllPhones();
      router.closeAll();
      expect(spy.handled.single.$2, isA<ToolList>());
      expect(sent.single.message, isA<ToolEnd>());
      expect(spy.gone, [phone, phone]);
      expect(spy.allGone, 2);
    });

    test('without an endpoint tool.* is ignored, like an older agent', () {
      final (router, sent) = _router();
      router.handle(phone, const ToolOpen(rid: 1, tool: 'k3f9za7q1m'));
      expect(sent, isEmpty);
    });
  });

  group('slot', () {
    test('not serving and answers unavailable until a proxy is set, then '
        'forwards', () {
      final slot = ToolEndpointSlot();
      final out = <OutboundMessage>[];
      slot.outbound.listen(out.add);
      expect(slot.serving, isFalse);
      slot.handle(phone, const ToolList());
      slot.handle(phone, const ToolOpen(rid: 4, tool: 'k3f9za7q1m'));
      slot.handle(
        phone,
        const ToolRequest(
          id: 9,
          tool: 'k3f9za7q1m',
          method: 'GET',
          target: '/',
          head: [],
          end: true,
        ),
      );
      slot.handle(phone, const ToolAck([9, 1]));
      expect(out.map((o) => o.message), [
        ToolListResult(available: false, body: emptyToolListingBody),
        const ToolOpened(rid: 4, ok: false, code: 'unavailable'),
        const ToolEnd(id: 9, code: 'unavailable'),
      ]);
      final spy = _SpyEndpoint();
      slot.target = spy;
      expect(slot.serving, isTrue);
      slot.handle(phone, const ToolList());
      spy.say(phone, const ToolEnd(id: 2));
      expect(spy.handled, hasLength(1));
      expect(out.last.message, const ToolEnd(id: 2));
      slot.phoneGone(phone);
      slot.allPhonesGone();
      expect(spy.gone, [phone]);
      expect(spy.allGone, 1);
      slot.target = null;
      expect(slot.serving, isFalse);
      spy.say(phone, const ToolEnd(id: 3));
      expect(out.last.message, const ToolEnd(id: 2), reason: 'unplugged');
    });
  });
}
