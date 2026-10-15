import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/ai/ai_phone.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import 'ai_fakes.dart';
import 'fake_local_sessions.dart';

/// The phone of these tests.
const testPhone = '33333333-3333-4333-8333-333333333333';

/// A window with real tabs and runtimes on fake agents, and its phone hub
/// (V2-2 D2): what a phone's requests reach, and what the hub sends back
/// ([out]). The container is disposed with the test.
final class PhoneHubRig {
  PhoneHubRig(FakeScenario scenario, {List<Override> more = const []})
    : fakes = FakeAiRuntimes(scenario) {
    c = cliContainer(
      FakeLocalSessions(),
      overrides: [...fakes.overrides, ...more],
    );
    hub = c.read(aiPhoneHubProvider);
    hub.outbound.listen(out.add);
  }

  final FakeAiRuntimes fakes;
  late final ProviderContainer c;
  late final AiPhoneHub hub;
  final out = <OutboundMessage>[];

  List<T> sent<T>() => out.map((o) => o.message).whereType<T>().toList();

  /// The last answer to request [rid].
  AiResult result(int rid) => sent<AiResult>().lastWhere((r) => r.rid == rid);

  /// The last listing the phone was sent.
  AiListing listing() {
    final r = sent<AiListResult>().last;
    return AiListing.fromJson(decodeBody(r.body)!, available: r.available);
  }

  String sidOf(TerminalTab tab) => hub.sidOf(tab.ai!.id);

  AiSessionState stateOf(TerminalTab tab) =>
      c.read(aiRuntimesProvider.notifier).existing(tab.ai!.id)!.state;

  /// [message] from the phone.
  void say(AiMessage message) => hub.handle(testPhone, message);

  /// Waits (real time, 2 s at most) until [test] holds.
  Future<void> until(bool Function() test) async {
    for (var i = 0; i < 400 && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(test(), isTrue, reason: 'condition not reached');
  }

  /// Waits for the answer to request [rid].
  Future<AiResult> answer(int rid) async {
    await until(() => sent<AiResult>().any((r) => r.rid == rid));
    return result(rid);
  }
}
