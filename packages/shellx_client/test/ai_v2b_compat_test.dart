import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

const _sid = 'x.1';

/// A window that lists AI sessions with [features], and answers a stop with
/// [stopAnswer] (made from the request's rid).
final class _Window implements AiEndpoint {
  _Window({this.features = const {}, this.stopAnswer});

  final Set<String> features;
  final AiResult Function(int rid)? stopAnswer;
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final received = <AiMessage>[];

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  void handle(String mobileId, AiMessage message) {
    received.add(message);
    switch (message) {
      case AiList():
        _say(
          AiListResult(
            available: true,
            body: encodeBody(AiListing(features: features).toJson()),
          ),
        );
      case AiCancel(:final rid):
        final answer = stopAnswer;
        if (answer != null) _say(answer(rid));
      default:
        break;
    }
  }

  @override
  void phoneGone(String mobileId) {}

  @override
  void allPhonesGone() {}

  void _say(AiMessage m) => _out.add(OutboundMessage(phoneId, m));
}

TypeMatcher<AiRequestException> _aiError(String code) =>
    isA<AiRequestException>().having((e) => e.code, 'code', code);

/// V2-2b B1 (R3, R15), Review Focus 2: a phone uses a V2-2b feature only
/// when the relay process says `ai` 2 or more AND the window's listing names
/// it — so a V2-2a desktop, or a V2-2b window behind a V2-2a background
/// service that would drop the new messages, never gets one and nobody waits
/// for an answer that cannot come.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('a V2-2b desktop: ai 2 from its list, and the features its listing '
      'names', () {
    fakeAsync((async) {
      final window = _Window(features: {AiFeature.config});
      final h = Harness(async, keys, ai: window);
      final ai = h.phoneMachine.ai;
      h.run(h.phoneMachine.connect());
      h.run(h.phoneMachine.listSessions(includeDesktop: true));
      h.run(ai.watch());
      async.elapse(const Duration(milliseconds: 100));
      expect(ai.protocol, 2);
      expect(ai.listing?.features, {'config'});
      expect(ai.can(AiFeature.config), isTrue);
      expect(ai.can(AiFeature.item), isFalse, reason: 'not named');
    });
  });

  test('the router says ai 1 (a V2-2a desktop, or a V2-2b window behind a '
      'V2-2a background service): no V2-2b feature, even one the listing '
      'names', () {
    fakeAsync((async) {
      final window = _Window(features: {AiFeature.config});
      final h = Harness(async, keys, ai: window, aiProtocol: 1);
      final ai = h.phoneMachine.ai;
      h.run(h.phoneMachine.connect());
      h.run(h.phoneMachine.listSessions(includeDesktop: true));
      h.run(ai.watch());
      async.elapse(const Duration(milliseconds: 100));
      expect(ai.protocol, 1);
      expect(ai.supported, isTrue, reason: 'V2-2a AI works as before');
      expect(ai.listing?.features, {'config'});
      expect(ai.can(AiFeature.config), isFalse);
    });
  });

  test('before any desktop list (a page opened from a push) nothing is '
      'known: no feature', () {
    fakeAsync((async) {
      final window = _Window(features: {AiFeature.config});
      final h = Harness(async, keys, ai: window);
      final ai = h.phoneMachine.ai;
      h.run(ai.watch());
      async.elapse(const Duration(milliseconds: 100));
      expect(ai.listing?.features, {'config'});
      expect(ai.protocol, isNull);
      expect(ai.can(AiFeature.config), isFalse);
    });
  });

  test('a computer without AI for phones: no protocol, no feature', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final ai = h.phoneMachine.ai;
      h.run(h.phoneMachine.connect());
      h.run(h.phoneMachine.listSessions(includeDesktop: true));
      expect((ai.supported, ai.protocol), (false, null));
      expect(ai.can(AiFeature.config), isFalse);
    });
  });

  group('a result\'s body reaches the caller (B4)', () {
    test('with its code, as the JSON object the computer sent', () {
      fakeAsync((async) {
        final window = _Window(
          stopAnswer: (rid) => AiResult(
            rid: rid,
            ok: false,
            code: 'confirm',
            body: encodeBody({
              'touched': ['src/a.ts'],
              'some_clean': true,
            }),
          ),
        );
        final h = Harness(async, keys, ai: window);
        final ai = h.phoneMachine.ai;
        h.run(h.phoneMachine.connect());
        expect(
          () => h.run(ai.cancel(_sid)),
          throwsA(
            _aiError('confirm').having((e) => e.body, 'body', {
              'touched': ['src/a.ts'],
              'some_clean': true,
            }),
          ),
        );
      });
    });

    test('none when it is no JSON object; never in toString', () {
      fakeAsync((async) {
        final window = _Window(
          stopAnswer: (rid) => AiResult(
            rid: rid,
            ok: false,
            code: 'refused',
            body: encodeBody({'x': 1}).sublist(1),
          ),
        );
        final h = Harness(async, keys, ai: window);
        final ai = h.phoneMachine.ai;
        h.run(h.phoneMachine.connect());
        AiRequestException? error;
        try {
          h.run(ai.cancel(_sid));
        } on AiRequestException catch (e) {
          error = e;
        }
        expect(error?.code, 'refused');
        expect(error?.body, isNull);
        expect(error.toString(), 'AiRequestException(refused)');
        expect(
          const AiRequestException(
            'confirm',
            body: {
              'touched': ['a'],
            },
          ).toString(),
          'AiRequestException(confirm)',
        );
      });
    });
  });
}
