import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/ui/window_coordinator.dart';
import 'package:shellx_desktop/src/ui/window_host.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';

final class _FakeWindowHost implements WindowHost {
  final List<String> calls = [];
  @override
  Future<void> show(Size size) async =>
      calls.add('show ${size.width.toInt()}x${size.height.toInt()}');
  @override
  Future<void> hide() async => calls.add('hide');
}

void main() {
  late TestHarness h;
  late ProviderContainer container;

  WindowRouter router() => container.read(windowRouterProvider.notifier);
  WindowState window() => container.read(windowRouterProvider);
  AgentController agent() => container.read(agentControllerProvider.notifier);
  AgentViewState agentState() => container.read(agentControllerProvider);
  TrayActions tray() => container.read(trayActionsProvider);

  Future<void> signedIn({
    Map<String, bool>? settings,
    List<TrustedDevice> trusted = const [],
  }) async {
    h = TestHarness(settings: settings);
    container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    container.listen(
      agentControllerProvider,
      (prev, next) => coordinateWindows(prev, next, router()),
    );
    await h.seedSignedIn();
    // The harness owns the process's one TrustedStore (binding ruling,
    // Task 9): seed through it, never through a second TrustedStore
    // instance over the same secure store.
    for (final device in trusted) {
      await h.trusted.add(device);
    }
    await agent().bootstrap(watchForWake: false);
  }

  /// Answers the confirm dialog currently shown.
  Future<void> answer(bool yes) async {
    await pumpEventQueue();
    window().confirm!.complete(yes);
    await pumpEventQueue();
  }

  group('WindowRouter', () {
    test('closing the QR window invalidates the pairing code', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const PairPhone());
      expect(window().route, isA<PairingRoute>());
      expect(agentState().pairing, isNotNull);

      router().close();

      expect(window().visible, isFalse);
      expect(h.runtime.pairingCancels, 1);
      expect(agentState().pairing, isNull);
    });

    test('a confirm on top of the QR window does not cancel pairing', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const PairPhone());
      final pending = router().confirm(
        ConfirmRequest(title: 't', body: 'b', confirmLabel: 'ok'),
      );
      router().close();
      expect(await pending, isFalse);
      expect(window().route, isA<PairingRoute>());
      expect(h.runtime.pairingCancels, 0);
    });

    test('closing onboarding counts as finishing it', () async {
      await signedIn();
      expect(window().route, isA<OnboardingRoute>());
      router().close();
      await pumpEventQueue();
      expect(agentState().onboardingDone, isTrue);
      expect(h.launchAtLogin.enabled, isTrue);
    });
  });

  group('coordinateWindows', () {
    test('startup signed out opens the login window', () async {
      h = TestHarness();
      container = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      container.listen(
        agentControllerProvider,
        (prev, next) => coordinateWindows(prev, next, router()),
      );
      await agent().bootstrap(watchForWake: false);
      expect(window().route, isA<LoginRoute>());
    });

    test('4002 while running brings the login window back', () async {
      await signedIn(settings: {'onboarding_done': true});
      expect(window().visible, isFalse);
      h.runtime.emitRelay(RelayConnectionState.revoked);
      await pumpEventQueue();
      expect(window().route, isA<LoginRoute>());
      expect(agentState().signedOutNotice, isTrue);
    });

    test('a phone finishing pairing closes the QR window', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const PairPhone());
      h.runtime.eventController.add(MobilePaired(phone('m1', 'Pixel')));
      await pumpEventQueue();
      expect(window().visible, isFalse);
    });

    test(
      'signing in from the login window hides it (onboarding already done)',
      () async {
        h = TestHarness(settings: {'onboarding_done': true});
        container = ProviderContainer.test(
          overrides: [desktopServicesProvider.overrideWithValue(h.services())],
        );
        container.listen(
          agentControllerProvider,
          (prev, next) => coordinateWindows(prev, next, router()),
        );
        await agent().bootstrap(watchForWake: false);
        expect(window().route, isA<LoginRoute>());
        await agent().signIn(
          email: 'a@b.co',
          password: '12345678',
          register: false,
        );
        expect(window().visible, isFalse);
      },
    );
  });

  group('TrayActions', () {
    List<SessionSummary> oneSession() => [
      SessionSummary(
        id: 1,
        index: 1,
        shell: 'zsh',
        createdAt: DateTime(2026),
        attachedMobileId: null,
      ),
    ];

    test(
      'remote access off with sessions asks first; cancel keeps it on',
      () async {
        await signedIn(settings: {'onboarding_done': true});
        h.runtime.currentSessions = oneSession();
        h.runtime.sessionController.add(null);

        final done = tray().handle(const ToggleRemoteAccess());
        await answer(false);
        await done;
        expect(agentState().remoteAccess, isTrue);

        final again = tray().handle(const ToggleRemoteAccess());
        await answer(true);
        await again;
        expect(agentState().remoteAccess, isFalse);
        expect(h.runtime.stopped, isTrue);
      },
    );

    test('remote access off without sessions does not ask', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const ToggleRemoteAccess());
      expect(agentState().remoteAccess, isFalse);
      expect(window().confirm, isNull);
    });

    test('revoke asks with the phone name, then revokes', () async {
      await signedIn(
        settings: {'onboarding_done': true},
        trusted: [phone('m1', 'iPhone của Phú')],
      );
      final done = tray().handle(const RevokeDevice('m1'));
      await pumpEventQueue();
      expect(window().confirm!.title, 'Revoke iPhone của Phú?');
      await answer(true);
      await done;
      expect(h.runtime.revoked, ['m1']);
    });

    test('sign out asks, signs out and shows the login window', () async {
      await signedIn(settings: {'onboarding_done': true});
      final done = tray().handle(const SignOut());
      await answer(true);
      await done;
      expect(agentState().phase, AuthPhase.signedOut);
      expect(window().route, isA<LoginRoute>());
    });

    test('quit with sessions asks, then shuts down and quits', () async {
      await signedIn(settings: {'onboarding_done': true});
      h.runtime.currentSessions = oneSession();
      h.runtime.sessionController.add(null);
      final done = tray().handle(const Quit());
      await answer(true);
      await done;
      expect(h.runtime.stopped, isTrue);
      expect(h.keepAwake.last, isFalse);
      expect(h.quits, 1);
    });

    test('close one session / all sessions go to the runtime', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const CloseSession(4));
      await tray().handle(const CloseAllSessions());
      expect(h.runtime.closedSessions, [4]);
      expect(h.runtime.closedAll, isTrue);
    });

    test(
      'reconnect goes straight to the controller, no confirmation',
      () async {
        await signedIn(settings: {'onboarding_done': true});
        await tray().handle(const Reconnect());
        expect(h.runtime.reconnects, 1);
        expect(window().confirm, isNull);
      },
    );

    test('a failing action is caught and surfaced as a notification, never '
        'thrown (binding ruling, Task 9)', () async {
      await signedIn(settings: {'onboarding_done': true});
      h.settings.fail = true;

      await tray().handle(const ToggleRemoteAccess());

      // Unchanged: the write failed before the state could update.
      expect(agentState().remoteAccess, isTrue);
      expect(h.notifier.shown, isNotEmpty);
    });
  });

  test(
    'WindowPresenter shows with the route size and hides when closed',
    () async {
      final host = _FakeWindowHost();
      final presenter = WindowPresenter(host);
      await presenter.apply(const WindowState(route: LoginRoute()));
      await presenter.apply(const WindowState(route: LoginRoute()));
      await presenter.apply(const WindowState(route: PairingRoute()));
      await presenter.apply(const WindowState());
      expect(host.calls, ['show 440x620', 'show 440x660', 'hide']);
    },
  );
}
