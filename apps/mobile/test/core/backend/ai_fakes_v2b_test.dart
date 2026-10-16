import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';

import '../../support/fakes.dart';

/// The V2-2b parts of the AI fakes act like `MachineAi` and the app's adapter: a list of the sessions teaches
/// the protocol, a feature needs protocol 2 and the listing, every listing's sessions are seen.
void main() {
  test('a list of the sessions teaches the protocol the test scripted; none, and nothing changes', () async {
    final machine = FakeMachineSession('a');
    machine.ai.supportedValue = true;
    await machine.listSessions();
    expect((machine.ai.protocol, machine.ai.supported), (null, true));
    machine.ai.listedProtocol = 2;
    await machine.listSessions();
    expect((machine.ai.protocol, machine.ai.supported), (2, true));
  });

  test('can() needs protocol 2 and the feature in the last listing', () {
    final ai = FakeAiMachine()..emitListing(const AiListing(features: {AiFeature.history}));
    expect(ai.can(AiFeature.history), isFalse);
    ai.protocolValue = 2;
    expect(ai.can(AiFeature.history), isTrue);
    expect(ai.can(AiFeature.config), isFalse);
  });

  test('seen() remembers the sessions of every listing emitted', () {
    final ai = FakeAiMachine()
      ..emitListing(
        const AiListing(
          sessions: [
            AiSessionInfo(
              sid: 'e.-1',
              agentId: 'claude',
              agentName: 'Claude',
              title: '',
              state: AiRemoteState.idle,
              acpSessionId: 'sess-1',
            ),
          ],
        ),
      )
      ..emitListing(const AiListing());
    expect(ai.seen('e.-1')!.acpSessionId, 'sess-1');
    expect(ai.seen('e.-2'), isNull);
  });
}
