import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

import '../support/fakes.dart';

void main() {
  late TestHarness h;
  late ProviderContainer container;

  AgentController controller() =>
      container.read(agentControllerProvider.notifier);
  AgentViewState state() => container.read(agentControllerProvider);

  void boot([TestHarness? harness]) {
    h = harness ?? TestHarness();
    container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
  }

  group('startup', () {
    test(
      'without a token: signed out, no runtime, no sleep assertion',
      () async {
        boot();
        await controller().bootstrap(watchForWake: false);
        expect(state().phase, AuthPhase.signedOut);
        expect(h.runtimes, isEmpty);
        expect(h.keepAwake.last, isFalse);
      },
    );

    test(
      'with a token: signed in, runtime started, trusted list loaded',
      () async {
        boot();
        await h.seedSignedIn();
        await h.trusted.add(phone('m1', 'iPhone của Phú'));
        await controller().bootstrap(watchForWake: false);
        expect(state().phase, AuthPhase.signedIn);
        expect(state().email, 'phu@example.com');
        expect(h.runtime.started, isTrue);
        expect(h.runtime.params.credentials.token, h.relay.token);
        expect(state().trusted.single.name, 'iPhone của Phú');
        expect(h.keepAwake.last, isTrue);
      },
    );

    test(
      'relay offline at startup: stays signed in and shows disconnected',
      () async {
        boot();
        await h.seedSignedIn();
        h.relay.offline = true;
        await controller().bootstrap(watchForWake: false);
        h.runtime.emitRelay(RelayConnectionState.disconnected);
        expect(state().phase, AuthPhase.signedIn);
        expect(state().relay, RelayConnectionState.disconnected);
        expect(h.notifier.shown, isEmpty);
      },
    );

    for (final key in ['auth_token', 'device_private_key']) {
      test('an unreadable keychain ($key) signs out and says so, without '
          'details', () async {
        boot();
        await h.seedSignedIn();
        h.secureStore.failingReads.add(key);

        await controller().bootstrap(watchForWake: false);

        expect(state().phase, AuthPhase.signedOut);
        expect(h.runtimes, isEmpty);
        expect(h.keepAwake.last, isFalse);
        final shown = h.notifier.shown.single;
        expect(shown.title, 'ShellX could not read your saved sign-in');
        expect(shown.body, 'Sign in again to allow remote access.');
        // Nothing is deleted: the keychain may work again next time.
        h.secureStore.failingReads.clear();
        expect(await h.secureStore.read('auth_token'), h.relay.token);
        // The rest of startup still ran: the update check went out.
        await pumpEventQueue();
        expect(h.relay.last('GET /v1/version'), isNotNull);
      });
    }

    test('signing in works after an unreadable keychain at startup', () async {
      boot();
      h.secureStore.failingReads.add('auth_token');
      await controller().bootstrap(watchForWake: false);
      h.secureStore.failingReads.clear();

      await controller().signIn(
        email: 'phu@example.com',
        password: 'correct horse',
        register: false,
      );

      expect(state().phase, AuthPhase.signedIn);
      expect(h.runtime.started, isTrue);
    });

    test('a token without device or user id counts as signed out', () async {
      boot();
      await h.secureStore.write('auth_token', h.relay.token);
      await controller().bootstrap(watchForWake: false);
      expect(state().phase, AuthPhase.signedOut);
      expect(h.runtimes, isEmpty);
      expect(h.notifier.shown, isEmpty);
    });
  });

  group('sign in', () {
    test(
      'login sends the agent device and stores normalized credentials',
      () async {
        boot();
        await controller().bootstrap(watchForWake: false);
        await controller().signIn(
          email: '  Phu@Example.COM ',
          password: 'correct horse',
          register: false,
        );

        final body =
            jsonDecode(h.relay.last('POST /v1/auth/login').body) as Map;
        expect(body['email'], 'phu@example.com');
        expect(body['password'], 'correct horse');
        final device = body['device'] as Map;
        expect(device['kind'], 'agent');
        expect(device['platform'], 'macos');
        expect(device['name'], 'Phus-MacBook-Pro');
        expect(
          fromBase64UrlNoPad(device['public_key'] as String),
          hasLength(32),
        );

        expect(await h.secureStore.read('auth_token'), h.relay.token);
        expect(await h.secureStore.read('device_id'), h.relay.deviceId);
        expect(await h.secureStore.read('user_id'), h.relay.userId);
        expect(await h.secureStore.read('email'), 'phu@example.com');
        expect(state().phase, AuthPhase.signedIn);
        expect(h.runtime.started, isTrue);
      },
    );

    test('register calls POST /v1/auth/register', () async {
      boot();
      await controller().signIn(
        email: 'new@example.com',
        password: '12345678',
        register: true,
      );
      expect(h.relay.routes, contains('POST /v1/auth/register'));
    });

    test('a rejected login throws ApiException and stores nothing', () async {
      boot();
      h.relay.failures['POST /v1/auth/login'] = (401, 'invalid_credentials');
      await expectLater(
        controller().signIn(
          email: 'a@b.co',
          password: 'wrongpass',
          register: false,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
      expect(await h.secureStore.read('auth_token'), isNull);
      expect(h.runtimes, isEmpty);
    });

    test('signing in to a different account clears the trusted list', () async {
      boot();
      await h.secureStore.write('user_id', 'old-user');
      await h.trusted.add(phone('m1', 'Old phone'));
      await controller().signIn(
        email: 'a@b.co',
        password: '12345678',
        register: false,
      );
      expect(await h.trusted.list(), isEmpty);
    });

    test(
      'signing in again to the same account keeps the trusted list',
      () async {
        boot();
        await h.secureStore.write('user_id', h.relay.userId);
        await h.trusted.add(phone('m1', 'iPhone'));
        await controller().signIn(
          email: 'a@b.co',
          password: '12345678',
          register: false,
        );
        expect(await h.trusted.list(), hasLength(1));
      },
    );
  });

  group('token revoked (4002 / 401)', () {
    test(
      'closes sessions, drops the token, keeps key + user + trusted list',
      () async {
        boot();
        await h.seedSignedIn();
        await h.trusted.add(phone('m1', 'iPhone'));
        await controller().bootstrap(watchForWake: false);
        final keyBefore = await h.secureStore.read('device_private_key');
        expect(keyBefore, isNotNull);

        h.runtime.emitRelay(RelayConnectionState.revoked);
        await pumpEventQueue();

        expect(state().phase, AuthPhase.signedOut);
        expect(state().signedOutNotice, isTrue);
        expect(h.runtime.stopped, isTrue);
        expect(h.runtime.closedAll, isTrue);
        expect(await h.secureStore.read('auth_token'), isNull);
        expect(await h.secureStore.read('user_id'), h.relay.userId);
        expect(await h.secureStore.read('device_private_key'), keyBefore);
        expect(await h.trusted.list(), hasLength(1));
        expect(h.relay.routes, isNot(contains('POST /v1/auth/logout')));
        expect(h.notifier.shown.single.title, h.l10n.notifySignedOutTitle);
        expect(h.keepAwake.last, isFalse);
      },
    );

    test(
      'AgentRevoked does the same, and a doubled signal notifies once',
      () async {
        boot();
        await h.seedSignedIn();
        await controller().bootstrap(watchForWake: false);
        h.runtime.eventController.add(const AgentRevoked());
        h.runtime.emitRelay(RelayConnectionState.revoked);
        await pumpEventQueue();
        expect(state().phase, AuthPhase.signedOut);
        expect(h.notifier.shown, hasLength(1));
      },
    );

    test(
      'next login: same user keeps pairings, another user clears them',
      () async {
        boot();
        await h.seedSignedIn();
        await h.trusted.add(phone('m1', 'iPhone'));
        await controller().bootstrap(watchForWake: false);
        h.runtime.emitRelay(RelayConnectionState.revoked);
        await pumpEventQueue();

        await controller().signIn(
          email: 'phu@example.com',
          password: '12345678',
          register: false,
        );
        expect(await h.trusted.list(), hasLength(1));

        h.runtime.emitRelay(RelayConnectionState.revoked);
        await pumpEventQueue();
        h.relay.userId = '33333333-3333-4333-8333-333333333333';
        await controller().signIn(
          email: 'other@example.com',
          password: '12345678',
          register: false,
        );
        expect(await h.trusted.list(), isEmpty);
      },
    );

    test('a 401 from change password also signs out', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.relay.failures['POST /v1/auth/password'] = (401, 'unauthorized');
      await expectLater(
        controller().changePassword('new password'),
        throwsA(isA<ApiException>()),
      );
      expect(state().phase, AuthPhase.signedOut);
    });

    test('a 401 from a revoke with remote access off also signs out', () async {
      boot(TestHarness(settings: {SettingKeys.remoteAccess: false}));
      await h.seedSignedIn();
      await h.trusted.add(phone('m1', 'iPhone'));
      await controller().bootstrap(watchForWake: false);
      h.relay.failures['DELETE /v1/pairings/${h.relay.deviceId}/m1'] = (
        401,
        'unauthorized',
      );
      await controller().revoke('m1');
      expect(state().phase, AuthPhase.signedOut);
      expect(await h.secureStore.read('auth_token'), isNull);
      expect(await h.trusted.list(), isEmpty);
    });

    test('a failing notification never escapes the 4002 handling', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.notifier.fail = true;
      h.keepAwake.fail = true;
      h.runtime.emitRelay(RelayConnectionState.revoked);
      await pumpEventQueue();
      expect(state().phase, AuthPhase.signedOut);
      expect(await h.secureStore.read('auth_token'), isNull);
    });
  });

  group('sign out', () {
    test(
      'closes sessions, calls logout, clears token and trusted list',
      () async {
        boot();
        await h.seedSignedIn();
        await h.trusted.add(phone('m1', 'iPhone'));
        await controller().bootstrap(watchForWake: false);
        final runtime = h.runtime;

        await controller().signOut();

        expect(runtime.stopped, isTrue);
        expect(runtime.closedAll, isTrue);
        final logout = h.relay.last('POST /v1/auth/logout');
        expect(h.relay.bearerOf(logout), 'Bearer ${h.relay.token}');
        expect(await h.trusted.list(), isEmpty);
        expect(await h.secureStore.read('auth_token'), isNull);
        expect(await h.secureStore.read('user_id'), isNull);
        expect(await h.secureStore.read('email'), 'phu@example.com');
        expect(state().phase, AuthPhase.signedOut);
        expect(state().relay, RelayConnectionState.stopped);
        expect(h.keepAwake.last, isFalse);
      },
    );

    test('still signs out locally when the relay is unreachable', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.relay.offline = true;
      await controller().signOut();
      expect(state().phase, AuthPhase.signedOut);
      expect(await h.secureStore.read('auth_token'), isNull);
    });

    test('the relay link is stopped before POST /v1/auth/logout', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      final runtime = h.runtime;
      bool? stoppedAtLogout;
      h.relay.onRequest = (request) {
        if (request.url.path == '/v1/auth/logout') {
          stoppedAtLogout = runtime.stopped;
        }
      };
      await controller().signOut();
      expect(stoppedAtLogout, isTrue);
    });

    test('keeps the device key', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      final key = await h.secureStore.read('device_private_key');
      await controller().signOut();
      expect(await h.secureStore.read('device_private_key'), key);
    });
  });

  group('change password', () {
    test('posts the new password with the agent token', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      await controller().changePassword('a new password');
      final request = h.relay.last('POST /v1/auth/password');
      expect(jsonDecode(request.body), {'new_password': 'a new password'});
      expect(h.relay.bearerOf(request), 'Bearer ${h.relay.token}');
    });

    test('weak_password is surfaced to the caller', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.relay.failures['POST /v1/auth/password'] = (400, 'weak_password');
      await expectLater(
        controller().changePassword('short'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'weak_password'),
        ),
      );
      expect(state().phase, AuthPhase.signedIn);
    });
  });

  group('remote access switch', () {
    test('off stops the runtime and is remembered across restarts', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      final first = h.runtime;

      await controller().setRemoteAccess(false);
      expect(first.stopped, isTrue);
      expect(state().relay, RelayConnectionState.stopped);
      expect(h.settings.values[SettingKeys.remoteAccess], isFalse);
      expect(h.keepAwake.last, isFalse);

      final restarted = TestHarness(settings: h.settings.values);
      await restarted.seedSignedIn();
      boot(restarted);
      await controller().bootstrap(watchForWake: false);
      expect(restarted.runtimes, isEmpty);
      expect(state().remoteAccess, isFalse);

      await controller().setRemoteAccess(true);
      expect(restarted.runtime.started, isTrue);
      expect(h.settings.values[SettingKeys.remoteAccess], isTrue);
    });

    test('turning it on twice at once starts one runtime', () async {
      boot(TestHarness(settings: {SettingKeys.remoteAccess: false}));
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      await Future.wait([
        controller().setRemoteAccess(true),
        controller().setRemoteAccess(true),
      ]);
      expect(h.runtimes, hasLength(1));
      await controller().setRemoteAccess(true);
      expect(h.runtimes, hasLength(1));
    });

    test(
      'on again while the old runtime is still stopping waits for that '
      'stop before starting a new one (no overlapping relay links)',
      () async {
        boot();
        await h.seedSignedIn();
        await controller().bootstrap(watchForWake: false);
        final first = h.runtime;
        final gate = first.stopGate = Completer<void>();

        final off = controller().setRemoteAccess(false);
        await pumpEventQueue();
        // Off shows at once, even though the relay stop is still settling.
        expect(state().relay, RelayConnectionState.stopped);
        final on = controller().setRemoteAccess(true);
        await pumpEventQueue();
        expect(h.runtimes, hasLength(1));

        gate.complete();
        await off;
        await on;
        expect(h.runtimes, hasLength(2));
        expect(h.runtime.started, isTrue);
        expect(state().relay, h.runtime.relayState);
      },
    );

    test('off, on, off while stopping starts nothing', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      final gate = h.runtime.stopGate = Completer<void>();
      final first = controller().setRemoteAccess(false);
      final second = controller().setRemoteAccess(true);
      final third = controller().setRemoteAccess(false);
      gate.complete();
      await Future.wait([first, second, third]);
      expect(h.runtimes, hasLength(1));
      expect(state().relay, RelayConnectionState.stopped);
    });

    test('while signed out it is only remembered', () async {
      boot();
      await controller().bootstrap(watchForWake: false);
      await controller().setRemoteAccess(false);
      await controller().setRemoteAccess(true);
      expect(h.runtimes, isEmpty);
      expect(h.settings.values[SettingKeys.remoteAccess], isTrue);
    });
  });

  group('pairing', () {
    test(
      'startPairing exposes the QR data; cancelPairing invalidates it',
      () async {
        boot();
        await h.seedSignedIn();
        await controller().bootstrap(watchForWake: false);

        final view = controller().startPairing()!;
        expect(view.uri.agentDeviceId, h.relay.deviceId);
        expect(state().pairing, same(view));

        controller().cancelPairing();
        expect(h.runtime.pairingCancels, 1);
        expect(state().pairing, isNull);
      },
    );

    test('no pairing while remote access is off', () async {
      boot(TestHarness(settings: {SettingKeys.remoteAccess: false}));
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      expect(controller().startPairing(), isNull);
    });

    test('MobilePaired closes the QR, refreshes trust and notifies', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      controller().startPairing();

      final device = phone('m9', 'Pixel 9');
      await h.trusted.add(device);
      h.runtime.eventController.add(MobilePaired(device));
      await pumpEventQueue();

      expect(state().pairing, isNull);
      expect(state().trusted.map((d) => d.mobileId), contains('m9'));
      expect(h.notifier.shown.last.title, 'Paired with Pixel 9');
    });
  });

  group('agent events', () {
    test('a phone opening a session raises a system notification', () async {
      boot(TestHarness(locale: const Locale('vi')));
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.runtime.eventController.add(
        const SessionOpenedByMobile(mobileName: 'iPhone của Phú', sessionId: 3),
      );
      await pumpEventQueue();
      expect(
        h.notifier.shown.last.title,
        'iPhone của Phú vừa mở phiên terminal',
      );
    });

    test('active channel count and session list follow the runtime', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.runtime.eventController.add(const ActiveChannelsChanged(2));
      h.runtime.currentSessions = [
        SessionSummary(
          id: 1,
          index: 1,
          shell: 'zsh',
          createdAt: DateTime(2026),
          attachedMobileId: 'm1',
        ),
      ];
      h.runtime.sessionController.add(null);
      await pumpEventQueue();
      expect(state().activeChannels, 2);
      expect(state().sessions.single.shell, 'zsh');
    });

    test('closing sessions goes to the runtime', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      controller().closeSession(4);
      expect(h.runtime.closedSessions, [4]);
      controller().closeAllSessions();
      expect(h.runtime.closedAll, isTrue);
    });

    test('a failing notification is not an unhandled error', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.notifier.fail = true;
      h.runtime.eventController.add(
        const SessionOpenedByMobile(mobileName: 'iPhone', sessionId: 1),
      );
      await pumpEventQueue();
      expect(h.notifier.shown, isEmpty);
    });
  });

  group('wake', () {
    test('computer woke up while disconnected: reconnect now', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.runtime.emitRelay(RelayConnectionState.disconnected);
      controller().handleWake();
      expect(h.runtime.reconnects, 1);
    });

    test(
      'never after 4001 (replaced): spec §12, no automatic reconnect',
      () async {
        boot();
        await h.seedSignedIn();
        await controller().bootstrap(watchForWake: false);
        h.runtime.emitRelay(RelayConnectionState.replaced);
        controller().handleWake();
        expect(h.runtime.reconnects, 0);
      },
    );

    test('nothing to do while connecting or connected', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      controller().handleWake();
      h.runtime.emitRelay(RelayConnectionState.connected);
      controller().handleWake();
      expect(h.runtime.reconnects, 0);
    });

    test('no runtime (signed out): nothing happens', () async {
      boot();
      await controller().bootstrap(watchForWake: false);
      controller().handleWake();
      expect(h.runtimes, isEmpty);
    });
  });

  group('reconnect (tray "Reconnect", binding ruling for 4001/replaced)', () {
    test('replaced: calls runtime.reconnectNow()', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.runtime.emitRelay(RelayConnectionState.replaced);
      controller().reconnect();
      expect(h.runtime.reconnects, 1);
    });

    test('no runtime (signed out): nothing happens', () async {
      boot();
      await controller().bootstrap(watchForWake: false);
      controller().reconnect();
      expect(h.runtimes, isEmpty);
    });
  });

  group('revoke', () {
    test('with the agent running, AgentService.revoke does the work', () async {
      boot();
      await h.seedSignedIn();
      await h.trusted.add(phone('m1', 'iPhone'));
      await controller().bootstrap(watchForWake: false);
      await controller().revoke('m1');
      expect(h.runtime.revoked, ['m1']);
      expect(state().trusted, isEmpty);
    });

    test(
      'with remote access off, trust is removed locally and DELETE is sent',
      () async {
        boot(TestHarness(settings: {SettingKeys.remoteAccess: false}));
        await h.seedSignedIn();
        final device = phone('m1', 'iPhone');
        await h.trusted.add(device);
        await controller().bootstrap(watchForWake: false);
        await controller().revoke('m1');
        expect(await h.trusted.list(), isEmpty);
        expect(state().trusted, isEmpty);
        final route = 'DELETE /v1/pairings/${h.relay.deviceId}/m1';
        expect(h.relay.routes, contains(route));
        // Only this pairing: a newer one of the same phone is never removed.
        expect(
          h.relay.last(route).url.queryParameters['pairing_id'],
          device.pairingId,
        );
        expect(state().phase, AuthPhase.signedIn);
      },
    );

    test('with remote access off, a failed DELETE still revokes', () async {
      boot(TestHarness(settings: {SettingKeys.remoteAccess: false}));
      await h.seedSignedIn();
      await h.trusted.add(phone('m1', 'iPhone'));
      await controller().bootstrap(watchForWake: false);
      h.relay.offline = true;
      await controller().revoke('m1');
      expect(await h.trusted.list(), isEmpty);
      expect(state().phase, AuthPhase.signedIn);
    });
  });

  group('switches', () {
    test('keep awake only while signed in with remote access on', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      expect(h.keepAwake.last, isTrue);
      await controller().setKeepAwake(false);
      expect(h.keepAwake.last, isFalse);
      expect(h.settings.values[SettingKeys.keepAwake], isFalse);
      await controller().setKeepAwake(true);
      await controller().setRemoteAccess(false);
      expect(h.keepAwake.last, isFalse);
    });

    test('keep awake off is remembered across restarts', () async {
      boot(TestHarness(settings: {SettingKeys.keepAwake: false}));
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      expect(state().keepAwake, isFalse);
      expect(h.keepAwake.last, isFalse);
    });

    test(
      'launch at startup: applied, persisted, reverted on OS failure',
      () async {
        boot();
        await controller().bootstrap(watchForWake: false);
        await controller().completeOnboarding();
        expect(h.launchAtLogin.enabled, isTrue);
        expect(h.settings.values[SettingKeys.onboardingDone], isTrue);
        expect(h.settings.values[SettingKeys.launchAtStartup], isTrue);

        h.launchAtLogin.fail = true;
        await controller().setLaunchAtStartup(false);
        expect(state().launchAtStartup, isTrue);
        expect(h.settings.values[SettingKeys.launchAtStartup], isTrue);
      },
    );

    test('after onboarding, the OS decides launch at startup', () async {
      boot(TestHarness(settings: {SettingKeys.onboardingDone: true}));
      h.launchAtLogin.enabled = false;
      await controller().bootstrap(watchForWake: false);
      expect(state().onboardingDone, isTrue);
      expect(state().launchAtStartup, isFalse);
    });
  });

  group('update check', () {
    test(
      'a newer agent version raises a notification that opens the download',
      () async {
        boot();
        h.relay.version = {
          ...h.relay.version,
          'latest_agent': {
            'version': '1.2.0',
            'mac_url':
                'https://download.shellx.pro/desktop/1.2.0/ShellX-1.2.0.dmg',
            'win_url':
                'https://download.shellx.pro/desktop/1.2.0/ShellX-Setup-1.2.0.exe',
          },
        };
        await controller().checkForUpdate();
        expect(state().update!.version, '1.2.0');
        expect(state().update!.required, isFalse);
        final shown = h.notifier.shown.single;
        expect(shown.title, 'ShellX 1.2.0 is available');
        shown.onClick!();
        expect(h.urlOpener.opened.single.path, endsWith('ShellX-1.2.0.dmg'));
      },
    );

    test('below min_agent: "needs to be updated"', () async {
      boot(TestHarness(appVersion: '0.9.0'));
      await controller().checkForUpdate();
      expect(state().update!.required, isTrue);
      expect(h.notifier.shown.single.title, h.l10n.notifyUpdateRequiredTitle);
    });

    test('a failed check is retried once the relay connects', () async {
      boot();
      await h.seedSignedIn();
      h.relay.offline = true;
      await controller().bootstrap(watchForWake: false);
      await pumpEventQueue();
      expect(state().update, isNull);

      h.relay.offline = false;
      h.relay.version = {
        ...h.relay.version,
        'latest_agent': {
          'version': '2.0.0',
          'mac_url': 'https://download.shellx.pro/a.dmg',
          'win_url': 'https://download.shellx.pro/a.exe',
        },
      };
      h.runtime.emitRelay(RelayConnectionState.connected);
      await pumpEventQueue();
      expect(state().update!.version, '2.0.0');
    });
  });

  group('one TrustedStore per process', () {
    test(
      'the runtime gets DesktopServices.trusted, also after a rebuild',
      () async {
        boot();
        await h.seedSignedIn();
        await controller().bootstrap(watchForWake: false);
        final first = h.runtime;
        expect(first.params.trusted, same(h.services().trusted));

        container.invalidate(agentControllerProvider);
        await controller().bootstrap(watchForWake: false);
        expect(first.stopped, isTrue);
        expect(h.runtimes, hasLength(2));
        expect(h.runtime.params.trusted, same(h.services().trusted));
      },
    );

    test('trust changes made by the agent show up without an event', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      await h.runtime.params.trusted.add(phone('m2', 'iPad'));
      await pumpEventQueue();
      expect(state().trusted.single.name, 'iPad');
    });
  });

  group('app version', () {
    DesktopServices servicesWith(String appVersion) {
      final base = TestHarness().services();
      return DesktopServices(
        secureStore: base.secureStore,
        settings: base.settings,
        api: base.api,
        runtimeFactory: base.runtimeFactory,
        keepAwake: base.keepAwake,
        launchAtLogin: base.launchAtLogin,
        notifier: base.notifier,
        urlOpener: base.urlOpener,
        l10n: base.l10n,
        appVersion: appVersion,
        platform: base.platform,
        deviceName: base.deviceName,
      );
    }

    test('must be PackageInfo.version: x.y.z without +build', () {
      expect(servicesWith('1.2.3').appVersion, '1.2.3');
      expect(() => servicesWith('1.0.0+1'), throwsA(isA<AssertionError>()));
    });

    test('PTY kills are waited for 3 s by default, with no seam', () {
      final services = servicesWith('1.0.0');
      expect(services.ptyKillTimeout, const Duration(seconds: 3));
      expect(services.awaitPtyKills, isNull);
    });
  });

  group('quit and PTY kills', () {
    test(
      'shutdown closes sessions, waits for the kills, then releases keep-awake',
      () async {
        boot();
        await h.seedSignedIn();
        await controller().bootstrap(watchForWake: false);
        final runtime = h.runtime;
        final kills = Completer<void>();
        bool? stoppedFirst;
        h.ptyKills = () {
          stoppedFirst = runtime.stopped;
          return kills.future;
        };

        var done = false;
        final shutdown = controller().shutdown().then((_) => done = true);
        await pumpEventQueue();
        expect(stoppedFirst, isTrue);
        expect(runtime.closedAll, isTrue);
        expect(h.ptyKillWaits, 1);
        expect(done, isFalse);
        expect(h.keepAwake.last, isTrue);

        kills.complete();
        await shutdown;
        expect(h.keepAwake.last, isFalse);
        expect(h.quits, 0); // Quitting itself is Task 9's call.
      },
    );

    test('shutdown gives up on kills after the timeout', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.ptyKills = () => Completer<void>().future;
      await controller().shutdown();
      expect(h.ptyKillWaits, 1);
      expect(h.keepAwake.last, isFalse);
    });

    test('shutdown never throws: failing seam and keep-awake', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.ptyKills = () => Future<void>.error(StateError('kill failed'));
      h.keepAwake.fail = true;
      await controller().shutdown();
      expect(h.runtime.stopped, isTrue);
    });

    test('shutdown with remote access off still waits for kills', () async {
      boot(TestHarness(settings: {SettingKeys.remoteAccess: false}));
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      await controller().shutdown();
      expect(h.ptyKillWaits, 1);
    });

    test('sign-out waits for the kills before reporting signed out', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      final runtime = h.runtime;
      final kills = Completer<void>();
      bool? stoppedFirst;
      h.ptyKills = () {
        stoppedFirst = runtime.stopped;
        return kills.future;
      };

      final signOut = controller().signOut();
      await pumpEventQueue();
      expect(stoppedFirst, isTrue);
      expect(state().phase, AuthPhase.signedIn);

      kills.complete();
      await signOut;
      expect(state().phase, AuthPhase.signedOut);
    });
  });

  test('disposing the container stops the runtime', () async {
    boot();
    await h.seedSignedIn();
    await controller().bootstrap(watchForWake: false);
    container.dispose();
    expect(h.runtime.stopped, isTrue);
  });
}
