import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';
import '../support/fake_pty.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

/// A router with an AI endpoint: [aiProtocol] as it is told, or its own
/// default when null.
(SessionRouter, List<OutboundMessage>) _router({int? aiProtocol}) {
  var next = 10;
  int ids() => next++;
  final shells = SessionManager(
    ptyFactory: FakePtyFactory(),
    shellResolver: const FixedShellResolver(),
    homeDirectory: '/Users/test',
    baseEnvironment: const {},
    nextId: ids,
  );
  final desktop = DesktopSessionManager(nextId: ids);
  final router = aiProtocol == null
      ? SessionRouter(
          shells: shells,
          desktop: desktop,
          desktopSharing: () => true,
          ai: AiEndpointSlot(),
        )
      : SessionRouter(
          shells: shells,
          desktop: desktop,
          desktopSharing: () => true,
          ai: AiEndpointSlot(),
          aiProtocol: aiProtocol,
        );
  final sent = <OutboundMessage>[];
  router.outbound.listen(sent.add);
  return (router, sent);
}

AiListing _listing(AiListResult r) =>
    AiListing.fromJson(decodeBody(r.body)!, available: r.available);

/// V2-2b B1 (R3): the two halves of a phone's "can": what the relay process
/// reports, and what the window's hub names in its listing.
void main() {
  group('the router reports the protocol of its process', () {
    test('kAiProtocol (2) by default', () {
      fakeAsync((async) {
        final (router, sent) = _router();
        router.handle(_phone, const SessionList(desktop: true));
        async.flushMicrotasks();
        expect((sent.single.message as SessionListResult).ai, 2);
      });
    });

    test('the one it is told: a test plays an older desktop', () {
      fakeAsync((async) {
        final (router, sent) = _router(aiProtocol: 1);
        router.handle(_phone, const SessionList(desktop: true));
        async.flushMicrotasks();
        expect((sent.single.message as SessionListResult).ai, 1);
      });
    });
  });

  group('the hub names what it does in its listing', () {
    test('every listing names the hub\'s features (AiPhoneHub.offered)', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(_phone, const AiList());
      final listing = _listing(rig.last<AiListResult>(_phone));
      expect(listing.features, AiPhoneHub.offered);
    });

    test('they stay when the listing is cut to fit one message', () {
      final source = FakeAiSource();
      for (var i = 1; i <= 400; i++) {
        source.add(-i, title: 'x' * 190);
      }
      final hub = AiPhoneHub(
        source: source,
        epoch: 'ep',
        features: {AiFeature.config, AiFeature.item},
      );
      final sent = <OutboundMessage>[];
      hub.outbound.listen(sent.add);
      hub.handle(_phone, const AiList());
      final result = sent.single.message as AiListResult;
      expect(result.body.length, lessThanOrEqualTo(kAiMaxBodyBytes));
      final listing = _listing(result);
      expect(listing.sessions.length, lessThan(400), reason: 'it was cut');
      expect(listing.features, {'config', 'item'});
    });
  });
}
