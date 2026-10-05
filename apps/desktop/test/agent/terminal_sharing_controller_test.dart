import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

import '../support/fakes.dart';

DesktopSessionSummary terminal(int id, {String? mobile}) =>
    DesktopSessionSummary(
      id: id,
      index: 1,
      app: 'Terminal',
      title: 'npm run dev',
      shell: 'zsh',
      createdAt: DateTime(2026, 10, 5),
      attachedMobileId: mobile,
      connected: true,
    );

void main() {
  late TestHarness h;
  late FakeSharingSetup setup;
  late ProviderContainer container;

  AgentController controller() =>
      container.read(agentControllerProvider.notifier);
  TerminalSharingView sharing() =>
      container.read(agentControllerProvider).terminalSharing;

  void boot({Map<String, bool>? settings, bool offered = true}) {
    setup = FakeSharingSetup();
    h = TestHarness(settings: settings, sharingSetup: offered ? setup : null);
    container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
  }

  Future<void> start() async {
    await controller().bootstrap(watchForWake: false);
    await controller().terminalSharingCheck;
  }

  group('startup', () {
    test('not offered: no switch, nothing checked', () async {
      boot(offered: false);
      await h.seedSignedIn();
      await start();
      expect(sharing().available, isFalse);
      expect(h.runtime.sharingCalls, isEmpty);
    });

    test(
      'off: switch shown off, a leftover bin is cleaned, server not started',
      () async {
        boot();
        await h.seedSignedIn();
        await start();
        expect(sharing().available, isTrue);
        expect(sharing().enabled, isFalse);
        expect(setup.calls, ['maintain:false']);
        expect(h.runtime.sharingCalls, isEmpty);
      },
    );

    test(
      'on: binary kept current, health checked, server started with the runtime',
      () async {
        boot(settings: {SettingKeys.terminalSharing: true});
        setup.needsSetupResult = true;
        await h.seedSignedIn();
        await start();
        expect(sharing().enabled, isTrue);
        expect(sharing().needsSetup, isTrue);
        expect(setup.calls, ['maintain:true', 'needsSetup']);
        expect(h.runtime.sharingCalls, [true]);
        // Startup never edits startup files (spec §10.2).
        expect(setup.calls, isNot(contains('enable')));
      },
    );

    test(
      'on, but the port cannot be opened: notified, switch stays on',
      () async {
        boot(settings: {SettingKeys.terminalSharing: true});
        h.sharingStartFails = true;
        await h.seedSignedIn();
        await start();
        expect(h.runtime.sharingCalls, [true]);
        expect(sharing().enabled, isTrue);
        expect(
          h.notifier.shown.single.title,
          h.l10n.notifyTerminalSharingStartFailedTitle,
        );
      },
    );
  });

  group('enable', () {
    test('installs, starts the server, remembers the switch', () async {
      boot();
      await h.seedSignedIn();
      await start();
      final plan = (await controller().prepareTerminalSharing())!;
      expect(await controller().enableTerminalSharing(plan), isTrue);
      expect(setup.calls, containsAllInOrder(['prepare', 'enable']));
      expect(h.runtime.sharingCalls, [true]);
      expect(h.settings.values[SettingKeys.terminalSharing], isTrue);
      expect(sharing().enabled, isTrue);
      expect(sharing().busy, isFalse);
    });

    test(
      'signed out (no runtime): files installed, server starts with the next runtime',
      () async {
        boot();
        await start();
        expect(await controller().enableTerminalSharing(setup.plan), isTrue);
        expect(h.runtimes, isEmpty);
        expect(sharing().enabled, isTrue);
      },
    );

    test('the installer fails: nothing on, notified', () async {
      boot();
      await h.seedSignedIn();
      await start();
      setup.failEnable = true;
      expect(await controller().enableTerminalSharing(setup.plan), isFalse);
      expect(sharing().enabled, isFalse);
      expect(h.runtime.sharingCalls, isEmpty);
      expect(h.settings.values[SettingKeys.terminalSharing], isNull);
      expect(
        h.notifier.shown.single.title,
        h.l10n.notifyTerminalSharingFailedTitle,
      );
    });

    test(
      'the server cannot start: files restored, switch off (spec §10.1 step 3)',
      () async {
        boot();
        await h.seedSignedIn();
        await start();
        h.runtime.failSharingStart = true;
        expect(await controller().enableTerminalSharing(setup.plan), isFalse);
        expect(setup.calls, containsAllInOrder(['enable', 'undo']));
        expect(sharing().enabled, isFalse);
        expect(h.settings.values[SettingKeys.terminalSharing], isNull);
        expect(
          h.notifier.shown.single.title,
          h.l10n.notifyTerminalSharingFailedTitle,
        );
      },
    );

    test('the switch cannot be saved: rolled back too', () async {
      boot();
      await h.seedSignedIn();
      await start();
      h.settings.fail = true;
      expect(await controller().enableTerminalSharing(setup.plan), isFalse);
      expect(setup.calls, contains('undo'));
      expect(h.runtime.sharingCalls, [true, false]);
      expect(sharing().enabled, isFalse);
    });
  });

  group('disable', () {
    test(
      'removes blocks, stops the server in between, forgets the switch',
      () async {
        boot(settings: {SettingKeys.terminalSharing: true});
        await h.seedSignedIn();
        await start();
        await controller().disableTerminalSharing();
        expect(setup.calls, containsAllInOrder(['disable', 'disabled']));
        expect(h.runtime.sharingCalls, [true, false]);
        expect(h.settings.values[SettingKeys.terminalSharing], isFalse);
        expect(sharing().enabled, isFalse);
        expect(sharing().needsSetup, isFalse);
      },
    );

    test('a file that could not be cleaned is reported', () async {
      boot(settings: {SettingKeys.terminalSharing: true});
      setup.failedFiles = ['/Users/phu/.zshrc'];
      await start();
      await controller().disableTerminalSharing();
      final shown = h.notifier.shown.single;
      expect(shown.title, h.l10n.notifyTerminalSharingDisableIncompleteTitle);
      expect(shown.body, '/Users/phu/.zshrc');
      expect(sharing().enabled, isFalse);
    });
  });

  group('desktop terminals', () {
    test('listed from the runtime, cleared when it stops', () async {
      boot(settings: {SettingKeys.terminalSharing: true});
      await h.seedSignedIn();
      await start();
      h.runtime.currentDesktopSessions = [terminal(7)];
      h.runtime.sessionController.add(null);
      expect(sharing().sessions.single.id, 7);
      await controller().setRemoteAccess(false);
      expect(sharing().sessions, isEmpty);
    });

    test('"Disconnect phone" goes to the runtime', () async {
      boot(settings: {SettingKeys.terminalSharing: true});
      await h.seedSignedIn();
      await start();
      controller().disconnectDesktopPhone(7);
      expect(h.runtime.disconnectedPhones, [7]);
    });

    test(
      'a phone attaching is notified once per 10 minutes per pair',
      () async {
        boot(settings: {SettingKeys.terminalSharing: true});
        await h.seedSignedIn();
        await h.trusted.add(phone('m1', 'Pixel của Phú'));
        await start();
        h.runtime.currentDesktopSessions = [terminal(7, mobile: 'm1')];
        h.runtime.attachedController.add(const DesktopPhoneAttached('m1', 7));
        await pumpEventQueue();
        expect(h.notifier.shown.map((n) => n.title), [
          'Pixel của Phú is viewing terminal Terminal — npm run dev',
        ]);

        // Re-attaching after a network drop: quiet.
        h.now = h.now.add(const Duration(minutes: 5));
        h.runtime.attachedController.add(const DesktopPhoneAttached('m1', 7));
        await pumpEventQueue();
        expect(h.notifier.shown, hasLength(1));

        h.now = h.now.add(const Duration(minutes: 5));
        h.runtime.attachedController.add(const DesktopPhoneAttached('m1', 7));
        await pumpEventQueue();
        expect(h.notifier.shown, hasLength(2));
      },
    );
  });
}
