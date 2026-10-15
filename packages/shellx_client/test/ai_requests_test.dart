import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

// The V2-2b requests of the phone's AI client against a scripted desktop:
// what goes out, what a body becomes, and what is never sent (B1, R15).

const _sid = 'x.1';

/// A desktop whose listing offers [features] and whose answers a test
/// scripts ([answer]; null: no answer); it records what the phone sends.
final class _Desktop implements AiEndpoint {
  _Desktop(this.features);

  Set<String> features;
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final received = <AiMessage>[];
  AiMessage? Function(AiMessage request)? answer;

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  void handle(String mobileId, AiMessage message) {
    received.add(message);
    final reply = message is AiList
        ? AiListResult(
            available: true,
            body: encodeBody(AiListing(features: features).toJson()),
          )
        : answer?.call(message);
    if (reply != null) _out.add(OutboundMessage(mobileId, reply));
  }

  @override
  void phoneGone(String mobileId) {}

  @override
  void allPhonesGone() {}

  List<T> got<T extends AiMessage>() => received.whereType<T>().toList();
}

Matcher _aiError(String code) =>
    isA<AiRequestException>().having((e) => e.code, 'code', code);

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  /// The phone, having listed the computer's sessions (the protocol) and
  /// watched its AI listing (the features).
  MachineAi ready(FakeAsync async, _Desktop d, {int aiProtocol = kAiProtocol}) {
    final h = Harness(async, keys, ai: d, aiProtocol: aiProtocol);
    h.run(h.phoneMachine.listSessions(includeDesktop: true));
    h.run(h.phoneMachine.ai.watch());
    settle(async);
    return h.phoneMachine.ai;
  }

  group('V2-2b B11: mode and model', () {
    test('the choices come as the computer sent them; a choice goes as id and '
        'value, a mode as mode', () {
      fakeAsync((async) {
        final d = _Desktop({AiFeature.config});
        final ai = ready(async, d);
        const view = AiConfigView(
          options: [
            AiConfigOptionView(
              id: 'model',
              name: 'Model',
              category: 'model',
              kind: 'select',
              current: 'opus',
              choices: [
                AiConfigChoiceView(value: 'opus', name: 'Opus 5.5'),
                AiConfigChoiceView(value: 'sonnet', name: 'Sonnet 5.5'),
              ],
            ),
          ],
        );
        d.answer = (m) => switch (m) {
          AiConfigGet(:final rid) => AiResult(
            rid: rid,
            ok: true,
            body: encodeConfigView(view),
          ),
          AiConfigSet(:final rid) => AiResult(rid: rid, ok: true),
          _ => null,
        };
        T run<T>(Future<T> f) => drive(async, f);
        final got = run(ai.config(_sid));
        expect(got.options.single.choices.map((c) => c.value), [
          'opus',
          'sonnet',
        ]);
        run(ai.setConfig(_sid, 'model', 'sonnet'));
        run(ai.setMode(_sid, 'plan'));
        expect(
          [for (final m in d.got<AiConfigSet>()) decodeBody(m.body)],
          [
            {'id': 'model', 'value': 'sonnet'},
            {'mode': 'plan'},
          ],
        );
      });
    });

    test('Review Focus 2, R15: a relay process that speaks ai 1, or a window '
        'that does not offer it — nothing is sent, unsupported at once', () {
      fakeAsync((async) {
        final old = _Desktop({AiFeature.config});
        final ai = ready(async, old, aiProtocol: 1);
        expect(ai.protocol, 1);
        expect(ai.can(AiFeature.config), isFalse);
        expect(
          () => drive(async, ai.config(_sid)),
          throwsA(_aiError('unsupported')),
        );
        expect(
          () => drive(async, ai.setConfig(_sid, 'model', 'x')),
          throwsA(_aiError('unsupported')),
        );
        expect(old.got<AiConfigGet>(), isEmpty);
        expect(old.got<AiConfigSet>(), isEmpty);

        final without = _Desktop(const {});
        final other = ready(async, without);
        expect(other.can(AiFeature.config), isFalse);
        expect(
          () => drive(async, other.setMode(_sid, 'plan')),
          throwsA(_aiError('unsupported')),
        );
        expect(without.got<AiConfigSet>(), isEmpty);
      });
    });

    test('a refusal comes with its code', () {
      fakeAsync((async) {
        final d = _Desktop({AiFeature.config});
        final ai = ready(async, d);
        d.answer = (m) => m is AiConfigSet
            ? AiResult(rid: m.rid, ok: false, code: 'on_computer')
            : null;
        expect(
          () => drive(async, ai.setConfig(_sid, 'mode', 'bypassPermissions')),
          throwsA(_aiError('on_computer')),
        );
      });
    });
  });
}
