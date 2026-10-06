import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/ui/activation.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/ui/dialogs/route_dialog.dart';
import 'package:shellx_desktop/src/ui/window_coordinator.dart';
import 'package:shellx_desktop/src/ui/window_host.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

/// A host whose calls take a while: each call waits for [gate].
final class _SlowWindowHost implements WindowHost {
  final List<String> calls = [];
  Completer<void> gate = Completer<void>();
  Future<void> _call(String name) async {
    calls.add('$name start');
    await gate.future;
    calls.add('$name end');
  }

  @override
  Future<void> show() => _call('show');
  @override
  Future<void> hide() => _call('hide');
  @override
  Future<void> bringToFront() => _call('front');
  @override
  Future<void> setTitle(String title) async {}
}

final class _FakeWindowHost implements WindowHost {
  final List<String> calls = [];
  @override
  Future<void> show() async => calls.add('show');
  @override
  Future<void> hide() async => calls.add('hide');
  @override
  Future<void> bringToFront() async => calls.add('front');
  @override
  Future<void> setTitle(String title) async => calls.add('title $title');
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

      expect(window().route, isNull);
      expect(window().visible, isTrue); // the terminal window stays
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

    test('closing onboarding when settings cannot be saved is no unhandled '
        'error', () async {
      await signedIn();
      h.settings.fail = true;
      router().close();
      await pumpEventQueue();
      expect(agentState().onboardingDone, isTrue);
      expect(h.notifier.shown, isNotEmpty);
    });
  });

  group('coordinateWindows', () {
    test(
      'startup signed out opens no dialog: the strip invites (D11)',
      () async {
        h = TestHarness();
        container = ProviderContainer.test(
          overrides: [desktopServicesProvider.overrideWithValue(h.services())],
        );
        container.listen(
          agentControllerProvider,
          (prev, next) => coordinateWindows(prev, next, router()),
        );
        await agent().bootstrap(watchForWake: false);
        expect(window().route, isNull);
      },
    );

    test('a user sign-out still shows the login dialog', () async {
      await signedIn(settings: {'onboarding_done': true});
      await agent().signOut();
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
      expect(window().route, isNull);
    });

    test(
      'signing in from the login window closes it (onboarding already done)',
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
        // D11: startup opens no login dialog; the strip's button does.
        router().open(const LoginRoute());
        await agent().signIn(
          email: 'a@b.co',
          password: '12345678',
          register: false,
        );
        expect(window().route, isNull);
      },
    );
  });

  group('handleActivation (launch, second launch, Dock, macOS reopen)', () {
    test(
      'signed out: the terminal window with one tab, no login dialog',
      () async {
        h = TestHarness();
        container = ProviderContainer.test(
          overrides: [desktopServicesProvider.overrideWithValue(h.services())],
        );
        await agent().bootstrap(watchForWake: false);
        await handleActivation(container);
        expect(window().terminal, isTrue);
        expect(window().route, isNull);
        expect(h.ptys.ptys, hasLength(1));
        expect(h.notifier.shown, isEmpty);
      },
    );

    test('again: the window comes forward, no second tab', () async {
      await signedIn(settings: {'onboarding_done': true});
      await handleActivation(container);
      router().hideWindow();
      await handleActivation(container);
      expect(window().visible, isTrue);
      expect(h.ptys.ptys, hasLength(1));
    });

    test('a phone-opened session counts as a tab (none is added)', () async {
      await signedIn(settings: {'onboarding_done': true});
      await h.sessions.handle(
        '33333333-3333-4333-8333-333333333333',
        const SessionOpen(cols: 80, rows: 24),
      );
      await pumpEventQueue();
      await handleActivation(container);
      expect(h.ptys.ptys, hasLength(1));
    });
  });

  group('window close (D9)', () {
    test(
      'hides the window, cancels an open confirm, keeps the shells',
      () async {
        await signedIn(settings: {'onboarding_done': true});
        await handleActivation(container);
        final pending = router().confirm(
          ConfirmRequest(title: 't', body: 'b', confirmLabel: 'ok'),
        );
        router().hideWindow();
        expect(await pending, isFalse);
        expect(window().visible, isFalse);
        expect(h.ptys.ptys.single.killed, isFalse);
      },
    );

    test('Escape-style close only closes the dialog', () async {
      await signedIn(settings: {'onboarding_done': true});
      await handleActivation(container);
      router().open(const ChangePasswordRoute());
      router().close();
      expect(window().route, isNull);
      expect(window().visible, isTrue);
    });
  });

  group('TrayActions', () {
    test('"Open terminal window" shows the window with a tab', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const OpenTerminalWindow());
      expect(window().terminal, isTrue);
      expect(h.ptys.ptys, hasLength(1));
    });

    test('a second ⌘Q while the quit confirm is open leaves one confirm and '
        'quits once', () async {
      await signedIn(settings: {'onboarding_done': true});
      await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      final first = tray().handle(const Quit());
      await pumpEventQueue();
      final second = tray().handle(const Quit());
      await pumpEventQueue();
      await first; // replaced: answered "no"
      expect(window().confirm, isNotNull);
      window().confirm!.complete(true);
      await second;
      expect(h.quits, 1);
      expect(h.ptys.ptys.single.killed, isTrue);
    });

    test('⌘Q again while quitting asks nothing and quits once', () async {
      await signedIn(settings: {'onboarding_done': true});
      await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      h.runtime.stopGate = Completer<void>();
      final first = tray().handle(const Quit());
      await answer(true); // shutting down: the relay stop hangs
      await tray().handle(const Quit());
      expect(window().confirm, isNull);
      h.runtime.stopGate!.complete();
      await first;
      expect(h.quits, 1);
    });

    test(
      'remote access off with a phone connected asks first; cancel keeps it on',
      () async {
        await signedIn(settings: {'onboarding_done': true});
        h.runtime.eventController.add(const ActiveChannelsChanged(1));
        await pumpEventQueue();

        final done = tray().handle(const ToggleRemoteAccess());
        await pumpEventQueue();
        expect(
          window().confirm!.body,
          'Connected phones will be disconnected. Terminal tabs on this '
          'computer keep running.',
        );
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

    test('remote access off with tabs but no phone does not ask', () async {
      await signedIn(settings: {'onboarding_done': true});
      await h.sessions.open(cols: 80, rows: 24);
      await tray().handle(const ToggleRemoteAccess());
      expect(agentState().remoteAccess, isFalse);
      expect(window().confirm, isNull);
      expect(h.ptys.ptys.single.killed, isFalse);
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

    test('quit with sessions asks, then kills every shell and quits', () async {
      await signedIn(settings: {'onboarding_done': true});
      await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      final done = tray().handle(const Quit());
      await answer(true);
      await done;
      expect(h.runtime.stopped, isTrue);
      expect(h.ptys.ptys.single.killed, isTrue);
      expect(h.keepAwake.last, isFalse);
      expect(h.quits, 1);
    });

    test('quit while signed out still asks about open tabs', () async {
      h = TestHarness();
      container = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      await agent().bootstrap(watchForWake: false);
      await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      final done = tray().handle(const Quit());
      await pumpEventQueue();
      expect(window().confirm, isNotNull);
      await answer(true);
      await done;
      expect(h.ptys.ptys.single.killed, isTrue);
      expect(h.quits, 1);
    });

    test(
      'quit always reaches quitApp, even when shutting down hangs',
      () async {
        await signedIn(settings: {'onboarding_done': true});
        await h.sessions.open(cols: 80, rows: 24);
        await pumpEventQueue();
        // A relay stop that never settles.
        h.runtime.stopGate = Completer<void>();
        final done = tray().handle(const Quit());
        await answer(true);
        await done;
        expect(h.runtime.stopped, isTrue);
        // The shells die before anything that can hang (A1 D7).
        expect(h.ptys.ptys.single.killed, isTrue);
        expect(h.quits, 1);
      },
    );

    test(
      'close one idle session at once; close all asks with the count first',
      () async {
        await signedIn(settings: {'onboarding_done': true});
        final id = await h.sessions.open(cols: 80, rows: 24);
        await h.sessions.open(cols: 80, rows: 24);
        await h.sessions.open(cols: 80, rows: 24);
        await pumpEventQueue();
        await tray().handle(CloseSession(id));
        expect(window().confirm, isNull); // idle: no question (D15)
        expect(h.ptys.ptys[0].killed, isTrue);
        await pumpEventQueue();

        final cancelled = tray().handle(const CloseAllSessions());
        await pumpEventQueue();
        expect(window().confirm!.title, 'Close all 2 tabs?');
        await answer(false);
        await cancelled;
        expect(h.ptys.ptys[1].killed, isFalse);

        final done = tray().handle(const CloseAllSessions());
        await answer(true);
        await done;
        expect(h.ptys.ptys[1].killed, isTrue);
        expect(h.ptys.ptys[2].killed, isTrue);
      },
    );

    test('close one session running a command asks first (D15, ruling '
        'I2)', () async {
      await signedIn(settings: {'onboarding_done': true});
      final id = await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      // Read the tabs once, so the window knows the session.
      container.read(terminalTabsProvider);
      h.ptys.ptys.single.emit('\x1b]133;C\x07');
      await pumpEventQueue();
      expect(
        container.read(terminalTabsProvider.notifier).needsCloseConfirm(id),
        isTrue,
      );

      final cancelled = tray().handle(CloseSession(id));
      await pumpEventQueue();
      expect(window().confirm!.title, 'Close “zsh 1”?');
      await answer(false);
      await cancelled;
      expect(h.ptys.ptys.single.killed, isFalse);

      final done = tray().handle(CloseSession(id));
      await answer(true);
      await done;
      expect(h.ptys.ptys.single.killed, isTrue);
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

  group('the window comes to the front (ruling C1)', () {
    late _FakeWindowHost host;

    /// Wires a presenter like main.dart and shows the window once.
    Future<void> shown() async {
      host = _FakeWindowHost();
      final presenter = WindowPresenter(host);
      container.listen<WindowState>(
        windowRouterProvider,
        (_, next) => presenter.apply(next),
        fireImmediately: true,
      );
      await handleActivation(container);
      await pumpEventQueue();
      expect(host.calls, ['show']);
      host.calls.clear();
    }

    test('every tray item that opens a dialog brings a shown window '
        'forward (minimized, behind, another Space)', () async {
      await signedIn(
        settings: {'onboarding_done': true},
        trusted: [phone('m1', 'Pixel')],
      );
      await shown();
      await tray().handle(const PairPhone());
      await pumpEventQueue();
      expect(host.calls, ['front']);
      router().close();
      await tray().handle(const OpenChangePassword());
      await pumpEventQueue();
      expect(host.calls, ['front', 'front']);
      router().close();
      final revoke = tray().handle(const RevokeDevice('m1'));
      await pumpEventQueue();
      expect(host.calls, ['front', 'front', 'front']);
      await answer(false);
      await revoke;
      final signOut = tray().handle(const SignOut());
      await pumpEventQueue();
      expect(host.calls, hasLength(4));
      await answer(false);
      await signOut;
      await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      final quit = tray().handle(const Quit());
      await pumpEventQueue();
      expect(host.calls, hasLength(5));
      await answer(false);
      await quit;
      final closeAll = tray().handle(const CloseAllSessions());
      await pumpEventQueue();
      expect(host.calls, hasLength(6));
      await answer(false);
      await closeAll;
      // Answering or closing a dialog never raises the window again.
      router().close();
      await pumpEventQueue();
      expect(host.calls, everyElement('front'));
      expect(host.calls, hasLength(6));
    });

    test(
      '"Sign in…" in the tray (signed out) brings the window forward',
      () async {
        h = TestHarness();
        container = ProviderContainer.test(
          overrides: [desktopServicesProvider.overrideWithValue(h.services())],
        );
        await agent().bootstrap(watchForWake: false);
        await shown();
        await tray().handle(const SignIn());
        await pumpEventQueue();
        expect(host.calls, ['front']);
      },
    );

    test('"Open terminal window", a Dock click after ⌘M and a second launch '
        'each bring the shown window forward', () async {
      await signedIn(settings: {'onboarding_done': true});
      await shown();
      await tray().handle(const OpenTerminalWindow());
      await handleActivation(container); // Dock reopen / second launch
      await handleActivation(container);
      await pumpEventQueue();
      expect(host.calls, ['front', 'front', 'front']);
      expect(h.ptys.ptys, hasLength(1)); // no extra tab
    });

    test(
      'a hidden window is shown (not raised twice) when a dialog opens',
      () async {
        await signedIn(settings: {'onboarding_done': true});
        await shown();
        router().hideWindow();
        await pumpEventQueue();
        await tray().handle(const PairPhone());
        await pumpEventQueue();
        expect(host.calls, ['hide', 'show']);
      },
    );
  });

  test('WindowPresenter shows once while anything is visible, hides when '
      'nothing is', () async {
    final host = _FakeWindowHost();
    final presenter = WindowPresenter(host);
    await presenter.apply(const WindowState(terminal: true));
    await presenter.apply(
      const WindowState(terminal: true, route: LoginRoute()),
    );
    await presenter.apply(const WindowState());
    await presenter.apply(const WindowState(route: PairingRoute()));
    expect(host.calls, ['show', 'hide', 'show']);
  });

  test('WindowPresenter runs host calls one after another: a quick '
      'hide → show cannot end with the Dock icon hidden', () async {
    final host = _SlowWindowHost();
    final presenter = WindowPresenter(host);
    final shown = presenter.apply(const WindowState(terminal: true));
    host.gate.complete();
    await shown;
    host.gate = Completer<void>();
    final hidden = presenter.apply(const WindowState());
    final again = presenter.apply(const WindowState(terminal: true));
    await pumpEventQueue();
    expect(host.calls.last, 'hide start');
    host.gate.complete();
    await hidden;
    await again;
    expect(host.calls, [
      'show start',
      'show end',
      'hide start',
      'hide end',
      'show start',
      'show end',
    ]);
  });

  test('WindowPresenter.settled waits for the queued show (A4 D18: the '
      'Dock badge after the policy)', () async {
    final host = _SlowWindowHost();
    final presenter = WindowPresenter(host);
    final shown = presenter.apply(const WindowState(terminal: true));
    var settled = false;
    unawaited(presenter.settled().then((_) => settled = true));
    await pumpEventQueue();
    expect(settled, isFalse);
    host.gate.complete();
    await shown;
    await pumpEventQueue();
    expect(settled, isTrue);
  });

  test('the native title is set only when it changes (ruling I3)', () async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final local = FakeLocalSessions();
    final c = ProviderContainer.test(
      overrides: [localSessionsProvider.overrideWithValue(local)],
    );
    final host = _FakeWindowHost();
    listenForWindowTitle(
      container: c,
      host: host,
      l10n: l10n,
      run: (call) => unawaited(call),
    );
    local.add(local.summary(1));
    await pumpEventQueue();
    expect(host.calls, ['title zsh 1 — ShellX']);
    for (var i = 0; i < 5; i++) {
      local.replace(local.summary(1, runningCommand: i.isEven));
      local.replace(
        local.summary(1, attachedMobileId: 'm1', driver: DriverSide.phone),
      );
    }
    await pumpEventQueue();
    expect(host.calls, hasLength(1));
    local.replace(local.summary(1, title: 'vim'));
    await pumpEventQueue();
    expect(host.calls, ['title zsh 1 — ShellX', 'title vim — ShellX']);
  });

  test('window title: "<tab> — ShellX", or "ShellX" without tabs', () async {
    final l10n = lookupAppLocalizations(const Locale('vi'));
    expect(windowTitleFor(null, l10n), 'ShellX');
    await signedIn(settings: {'onboarding_done': true});
    await handleActivation(container);
    final tab = container.read(terminalTabsProvider).selected!;
    expect(windowTitleFor(tab, l10n), '${tab.label} — ShellX');
    expect(tab.label, isNotEmpty);
  });

  test('dialog widths follow UI §4 (heights follow the content)', () {
    expect(dialogWidthFor(const WindowState(route: LoginRoute())), 400);
    expect(dialogWidthFor(const WindowState(route: OnboardingRoute())), 480);
    expect(
      dialogWidthFor(
        WindowState(
          confirm: ConfirmRequest(
            title: 't',
            body: 'b',
            confirmLabel: 'ok',
            long: true,
          ),
        ),
      ),
      520,
    );
  });
}
