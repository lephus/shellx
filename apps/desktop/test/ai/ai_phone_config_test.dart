import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' hide AgentReady;
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_phone.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

const _phone = '33333333-3333-4333-8333-333333333333';

/// Claude's own `configOptions` (adapter 0.90.0, trimmed).
const _claudeOptions = <Map<String, Object?>>[
  {
    'id': 'mode',
    'name': 'Mode',
    'category': 'mode',
    'type': 'select',
    'currentValue': 'default',
    'options': [
      {'value': 'default', 'name': 'Manual'},
      {'value': 'acceptEdits', 'name': 'Accept edits'},
      {'value': 'plan', 'name': 'Plan'},
      {'value': 'bypassPermissions', 'name': 'Bypass permissions'},
    ],
  },
  {
    'id': 'model',
    'name': 'Model',
    'category': 'model',
    'type': 'select',
    'currentValue': 'opus',
    'options': [
      {'value': 'opus', 'name': 'Opus 5.5'},
      {'value': 'sonnet', 'name': 'Sonnet 5.5'},
    ],
  },
];

/// A second source over the same window, to drive a control directly.
final _source = Provider<DesktopAiSource>((ref) {
  final source = DesktopAiSource(ref);
  ref.onDispose(source.dispose);
  return source;
});

/// V2-2b B11 on the computer: a phone's mode and model reach the agent as
/// the composer's chips do; a mode acting without asking never does.
void main() {
  late ProviderContainer c;
  late FakeAiRuntimes fakes;
  late AiPhoneHub hub;
  final out = <OutboundMessage>[];

  void boot(FakeScenario scenario) {
    out.clear();
    fakes = FakeAiRuntimes(scenario);
    c = cliContainer(FakeLocalSessions(), overrides: fakes.overrides);
    hub = c.read(aiPhoneHubProvider);
    hub.outbound.listen(out.add);
  }

  AiResult result(int rid) => out
      .map((o) => o.message)
      .whereType<AiResult>()
      .firstWhere((r) => r.rid == rid);

  Future<void> until(bool Function() test) async {
    for (var i = 0; i < 400 && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(test(), isTrue, reason: 'condition not reached');
  }

  bool answered(int rid) =>
      out.map((o) => o.message).whereType<AiResult>().any((r) => r.rid == rid);

  /// An AI tab whose agent a phone started; its session id.
  Future<(TerminalTab, String)> running() async {
    final tab = openTestAiTab(c, cwd: testAiCwd, select: false);
    final sid = hub.sidOf(tab.ai!.id);
    hub.handle(_phone, AiAttach(sid: sid));
    await until(
      () =>
          c
              .read(aiRuntimesProvider.notifier)
              .existing(tab.ai!.id)
              ?.state
              .phase ==
          AgentPhase.ready,
    );
    return (tab, sid);
  }

  test('the phone gets the choices without "Bypass permissions"; its choice '
      'reaches the agent and is remembered as the chip remembers it', () async {
    boot(const FakeScenario(configOptions: _claudeOptions));
    final (_, sid) = await running();
    hub.handle(_phone, AiConfigGet(sid: sid, rid: 1));
    await until(() => answered(1));
    final view = AiConfigView.fromJson(decodeBody(result(1).body)!);
    expect(view.options.first.choices.map((c) => c.value), [
      'default',
      'acceptEdits',
      'plan',
    ]);
    hub.handle(
      _phone,
      AiConfigSet(
        sid: sid,
        rid: 2,
        body: encodeBody({'id': 'model', 'value': 'sonnet'}),
      ),
    );
    await until(() => answered(2));
    expect(result(2).ok, isTrue);
    expect(
      fakes.agent().received,
      contains('session/set_config_option:model=sonnet'),
    );
    expect(rememberedConfig(c.read(settingsStoreProvider), 'claude'), {
      'model': 'sonnet',
    });
  });

  test(
    'Review Focus 5: "Bypass permissions" from a phone stays on the '
    'computer — refused by the hub, and by the window\'s own control',
    () async {
      boot(const FakeScenario(configOptions: _claudeOptions));
      final (tab, sid) = await running();
      hub.handle(
        _phone,
        AiConfigSet(
          sid: sid,
          rid: 3,
          body: encodeBody({'id': 'mode', 'value': 'bypassPermissions'}),
        ),
      );
      await until(() => answered(3));
      expect(result(3).code, 'on_computer');
      final control = c.read(_source).control(tab.ai!.id)!;
      await expectLater(
        control.setConfig('mode', 'bypassPermissions'),
        throwsA(isA<AiRefused>().having((r) => r.code, 'code', 'on_computer')),
      );
      await expectLater(
        control.setMode('yolo'),
        throwsA(isA<AiRefused>().having((r) => r.code, 'code', 'on_computer')),
      );
      expect(
        fakes.agent().received.where((m) => m.startsWith('session/set_')),
        isEmpty,
      );
      expect(
        rememberedConfig(c.read(settingsStoreProvider), 'claude'),
        isEmpty,
      );
    },
  );

  test('an agent with only modes: its modes, without one acting without '
      'asking; a mode is set as the mode chip sets it', () async {
    boot(
      const FakeScenario(
        modes: {
          'currentModeId': 'default',
          'availableModes': [
            {'id': 'default', 'name': 'Default'},
            {'id': 'plan', 'name': 'Plan'},
            {'id': 'yolo', 'name': 'YOLO'},
          ],
        },
      ),
    );
    final (_, sid) = await running();
    hub.handle(_phone, AiConfigGet(sid: sid, rid: 4));
    await until(() => answered(4));
    final view = AiConfigView.fromJson(decodeBody(result(4).body)!);
    expect(view.modes!.choices.map((c) => c.value), ['default', 'plan']);
    hub.handle(
      _phone,
      AiConfigSet(sid: sid, rid: 5, body: encodeBody({'mode': 'plan'})),
    );
    await until(() => answered(5));
    expect(result(5).ok, isTrue);
    expect(fakes.agent().received, contains('session/set_mode:plan'));
  });
}
