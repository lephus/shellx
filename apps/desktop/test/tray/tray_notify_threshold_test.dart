import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/agent/notify_threshold.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';

import '../support/fakes.dart';

void main() {
  test('choosing a threshold in the tray stores it; the agent reads it live '
      '(push spec §7)', () async {
    final h = TestHarness();
    final container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    await h.seedSignedIn();
    await container
        .read(agentControllerProvider.notifier)
        .bootstrap(watchForWake: false);
    expect(notifyThreshold(h.settings), const Duration(seconds: 30));

    await container
        .read(trayActionsProvider)
        .handle(const SetNotifyThreshold(10));
    expect(container.read(agentControllerProvider).notifyThresholdSeconds, 10);
    expect(notifyThreshold(h.settings), const Duration(seconds: 10));

    await container
        .read(trayActionsProvider)
        .handle(const SetNotifyThreshold(0));
    expect(notifyThreshold(h.settings), isNull);
  });

  test(
    'a stored value that is not one of the choices reads as the default',
    () {
      final settings = InMemorySettingsStore();
      expect(notifyThresholdSeconds(settings), 30);
      settings.ints[SettingKeys.notifyThreshold] = 45;
      expect(notifyThreshold(settings), const Duration(seconds: 30));
      settings.ints[SettingKeys.notifyThreshold] = 300;
      expect(notifyThreshold(settings), const Duration(minutes: 5));
    },
  );
}
