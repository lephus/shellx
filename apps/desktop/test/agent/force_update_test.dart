import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/agent/ui_services.dart';
import 'package:shellx_desktop/src/agent/update_check.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

import '../support/fakes.dart';

/// Contract §5 (force update): below `min_agent` the agent stops remote
/// access and keeps it stopped until a later check lifts the block.
void main() {
  late TestHarness h;
  late ProviderContainer container;

  AgentController controller() =>
      container.read(agentControllerProvider.notifier) as AgentController;
  AgentViewState state() => container.read(agentControllerProvider);

  void boot([TestHarness? harness]) {
    h = harness ?? TestHarness();
    container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
  }

  /// What the relay answers: [min] is `min_agent` (this build is 1.0.0).
  void relayAnswers({String min = '1.0.0', String latest = '1.0.0'}) {
    h.relay.version = {
      'min_agent': min,
      'min_mobile': '1.0.0',
      'latest_agent': {
        'version': latest,
        'mac_url': 'https://download.shellx.pro/desktop/$latest/a.dmg',
        'win_url': 'https://download.shellx.pro/desktop/$latest/a.exe',
      },
    };
  }

  Future<void> signedIn([TestHarness? harness]) async {
    boot(harness);
    await h.seedSignedIn();
    await controller().bootstrap(watchForWake: false);
    await pumpEventQueue();
  }

  test('contract §1: the window\'s services report the app version on '
      'every ShellxApi they make', () {
    final services = buildUiServices(
      settings: InMemorySettingsStore(),
      notifier: RecordingNotifier(),
      l10n: TestHarness().l10n,
      appVersion: '1.2.3',
      relayBase: Uri.parse('https://relay.test'),
      deviceName: 'Mac',
      sharingSetup: null,
      quitApp: () async {},
      windows: false,
    );
    expect(services.api.clientVersion, '1.2.3');
    final created = services.createApi();
    addTearDown(created.close);
    expect(created.clientVersion, '1.2.3');
  });

  test('checks every 6 h by default (was 24 h)', () {
    expect(kUpdateCheckInterval, const Duration(hours: 6));
    expect(TestHarness().services().updateInterval, kUpdateCheckInterval);
  });

  group('an update becomes required', () {
    test('remote access stops like the switch: phones let go, shells kept, '
        'no sleep assertion; the switch itself stays on', () async {
      await signedIn();
      await h.sessions.open(cols: 80, rows: 24);
      final runtime = h.runtime;
      expect(h.keepAwake.last, isTrue);

      relayAnswers(min: '1.1.0', latest: '1.1.0');
      await controller().checkForUpdate();

      expect(state().updateRequired, isTrue);
      expect(state().update!.version, '1.1.0');
      expect(runtime.stopped, isTrue);
      expect(runtime.phonesDisconnected, isTrue);
      expect(controller().runtime, isNull);
      expect(state().relay, RelayConnectionState.stopped);
      expect(h.keepAwake.last, isFalse);
      expect(h.ptys.ptys.single.killed, isFalse);
      expect(h.sessions.sessions, hasLength(1));
      expect(state().remoteAccess, isTrue);
      expect(h.notifier.shown.single.title, h.l10n.notifyUpdateRequiredTitle);
    });

    test(
      'at startup: the runtime the saved sign-in started is stopped',
      () async {
        await signedIn(TestHarness(appVersion: '0.9.0'));
        expect(state().updateRequired, isTrue);
        expect(h.runtimes.single.stopped, isTrue);
        expect(controller().runtime, isNull);
      },
    );

    test('nothing starts the runtime again meanwhile: the switch, a sign-in, '
        'a wake, Reconnect', () async {
      await signedIn();
      relayAnswers(min: '1.1.0', latest: '1.1.0');
      await controller().checkForUpdate();

      await controller().setRemoteAccess(false);
      await controller().setRemoteAccess(true);
      expect(h.settings.values[SettingKeys.remoteAccess], isTrue);
      await controller().signIn(
        email: 'phu@example.com',
        password: 'correct horse',
        register: false,
      );
      controller().handleWake();
      await controller().reconnect();
      expect(await controller().startPairing(), isNull);

      expect(h.runtimes, hasLength(1));
      expect(controller().runtime, isNull);
      expect(h.keepAwake.last, isFalse);
    });

    test('a failed check keeps the block', () async {
      await signedIn();
      relayAnswers(min: '1.1.0', latest: '1.1.0');
      await controller().checkForUpdate();
      h.relay.offline = true;
      await controller().checkForUpdate();
      expect(await controller().checkForUpdateNow(), isA<Failed>());
      expect(state().updateRequired, isTrue);
      expect(h.runtimes, hasLength(1));
    });

    test('"Check for updates" (Settings) blocks the same way', () async {
      await signedIn();
      relayAnswers(min: '1.1.0', latest: '1.1.0');
      final result = await controller().checkForUpdateNow();
      expect((result as Available).notice.required, isTrue);
      expect(state().updateRequired, isTrue);
      expect(h.runtime.stopped, isTrue);
    });
  });

  group('a later check no longer requires it (min_agent lowered)', () {
    test('the block lifts and the runtime starts again', () async {
      await signedIn();
      relayAnswers(min: '1.1.0', latest: '1.1.0');
      await controller().checkForUpdate();

      relayAnswers(min: '1.0.0', latest: '1.1.0');
      await controller().checkForUpdate();

      expect(state().updateRequired, isFalse);
      // A newer version is still offered, only no longer required.
      expect(state().update!.required, isFalse);
      expect(h.runtimes, hasLength(2));
      expect(h.runtime.started, isTrue);
      expect(controller().runtime, same(h.runtime));
      expect(h.keepAwake.last, isTrue);
    });

    test('with remote access off it stays off', () async {
      await signedIn(TestHarness(settings: {SettingKeys.remoteAccess: false}));
      relayAnswers(min: '1.1.0', latest: '1.1.0');
      await controller().checkForUpdate();
      relayAnswers();
      await controller().checkForUpdate();
      expect(state().update, isNull);
      expect(h.runtimes, isEmpty);
    });

    test('the switch turned on while blocked applies once it lifts', () async {
      await signedIn(TestHarness(settings: {SettingKeys.remoteAccess: false}));
      relayAnswers(min: '1.1.0', latest: '1.1.0');
      await controller().checkForUpdate();
      await controller().setRemoteAccess(true);
      expect(h.runtimes, isEmpty);

      relayAnswers();
      await controller().checkForUpdate();
      expect(h.runtimes, hasLength(1));
      expect(h.runtime.started, isTrue);
    });

    test('"Check for updates" (Settings) lifts it the same way', () async {
      await signedIn();
      relayAnswers(min: '1.1.0', latest: '1.1.0');
      await controller().checkForUpdate();
      relayAnswers();
      expect(await controller().checkForUpdateNow(), isA<UpToDate>());
      expect(state().update, isNull);
      expect(h.runtimes, hasLength(2));
      expect(h.runtime.started, isTrue);
    });

    test('the 6 h timer keeps checking while blocked (no relay link to '
        'retry on) and lifts the block', () {
      fakeAsync((fa) {
        boot(TestHarness(appVersion: '0.9.0'));
        unawaited(h.seedSignedIn());
        fa.flushMicrotasks();
        unawaited(controller().bootstrap(watchForWake: false));
        fa.flushMicrotasks();
        expect(state().updateRequired, isTrue);
        expect(h.runtimes.single.stopped, isTrue);

        relayAnswers(min: '0.9.0', latest: '1.0.0');
        fa.elapse(const Duration(hours: 5, minutes: 59));
        expect(state().updateRequired, isTrue);
        fa.elapse(const Duration(minutes: 1));
        expect(state().updateRequired, isFalse);
        expect(h.runtimes, hasLength(2));
        expect(h.runtime.started, isTrue);
        container.dispose();
      });
    });
  });

  group('reminders (the check runs every 6 h, reminders stay daily)', () {
    test('the same notice is notified once a day; a new one at once', () async {
      boot();
      relayAnswers(latest: '1.2.0');
      await controller().checkForUpdate();
      expect(h.notifier.shown, hasLength(1));

      h.now = h.now.add(const Duration(hours: 6));
      await controller().checkForUpdate();
      expect(h.notifier.shown, hasLength(1));

      h.now = h.now.add(const Duration(hours: 18));
      await controller().checkForUpdate();
      expect(h.notifier.shown, hasLength(2));

      // Required now: notified at once.
      relayAnswers(min: '1.2.0', latest: '1.2.0');
      await controller().checkForUpdate();
      expect(h.notifier.shown, hasLength(3));
      expect(h.notifier.shown.last.title, h.l10n.notifyUpdateRequiredTitle);

      // Another version: at once too.
      relayAnswers(min: '1.2.0', latest: '1.3.0');
      await controller().checkForUpdate();
      expect(h.notifier.shown, hasLength(4));
    });
  });
}
