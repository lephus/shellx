import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/push_controller.dart';
import 'package:toastification/toastification.dart';

import '../../support/fake_biometrics.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_push.dart';
import '../../support/fakes.dart';

const message = PushMessage(
  title: 'MacBook · Phiên 1',
  body: '✓ npm test · 3 phút 12 giây',
  data: {'agent_id': agentA, 'session_id': '101', 'kind': 'command'},
);

void main() {
  late FakePushMessaging messaging;
  late FakeBackend backend;
  late FakeSessionHolder session;
  late SharedPreferences prefs;
  late RecordingOpener opener;
  late FakePopupHandler popup;
  late FakeBiometricAuthenticator biometrics;
  late bool lockEnabled;
  late AppLockController lock;
  late PushController controller;

  PushController build({DevicePlatform platform = DevicePlatform.ios}) => PushController(
    messaging: messaging,
    session: session,
    prefs: prefs,
    opener: opener,
    device: DeviceDescription(name: 'iPhone 15', platform: platform),
    lock: lock,
    popup: () => popup,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    messaging = FakePushMessaging();
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    session = FakeSessionHolder(backend);
    opener = RecordingOpener();
    popup = FakePopupHandler();
    biometrics = FakeBiometricAuthenticator();
    lockEnabled = false;
    lock = AppLockController(authenticator: biometrics, isEnabled: () => lockEnabled);
    controller = build();
  });

  tearDown(() => controller.dispose());

  group('permission', () {
    test('asked once, after the machine list shows a paired machine; granted registers the token', () async {
      controller.start();
      await pumpEventQueue();
      expect(messaging.requests, 0);
      expect(backend.pushTokens, isEmpty);

      controller.onPairedMachines(0);
      await pumpEventQueue();
      expect(messaging.requests, 0);

      controller.onPairedMachines(1);
      await pumpEventQueue();
      expect(messaging.requests, 1);
      expect(controller.permission.value, PushPermission.granted);
      expect(backend.pushTokens, [('fcm-1', PushPlatform.ios)]);
      expect(controller.asked, isTrue);

      controller.onPairedMachines(2);
      await pumpEventQueue();
      expect(messaging.requests, 1);
    });

    test('locked (first launch after an update): the prompt waits until the app is unlocked', () async {
      lockEnabled = true;
      lock.lockOnLaunch();
      controller.start();
      controller.onPairedMachines(1);
      controller.onPairedMachines(1);
      await pumpEventQueue();
      expect(messaging.requests, 0);

      expect(await lock.unlock('Mở khóa ShellX'), isTrue);
      await pumpEventQueue();
      expect(messaging.requests, 1);
      expect(backend.pushTokens, hasLength(1));
    });

    test('a refusal is never asked again automatically, also after a restart', () async {
      messaging.answer = PushPermission.denied;
      controller.start();
      controller.onPairedMachines(1);
      await pumpEventQueue();
      expect(controller.permission.value, PushPermission.denied);
      expect(backend.pushTokens, isEmpty);

      controller.dispose();
      controller = build()..start();
      controller.onPairedMachines(1);
      await pumpEventQueue();
      expect(messaging.requests, 1);
      expect(controller.permission.value, PushPermission.denied);
    });

    test('Android 13 reports "denied" before the prompt: the prompt still shows once', () async {
      messaging.current = PushPermission.denied;
      controller = build(platform: DevicePlatform.android)..start();
      controller.onPairedMachines(1);
      await pumpEventQueue();
      expect(messaging.requests, 1);
      expect(backend.pushTokens, [('fcm-1', PushPlatform.android)]);
    });

    test('granted later in the system settings: refreshPermission registers the token', () async {
      messaging.current = PushPermission.denied;
      controller.start();
      await pumpEventQueue();
      expect(backend.pushTokens, isEmpty);

      messaging.current = PushPermission.granted;
      expect(await controller.refreshPermission(), PushPermission.granted);
      expect(backend.pushTokens, hasLength(1));
      // Already registered for this sign-in: not sent again.
      await controller.refreshPermission();
      expect(backend.pushTokens, hasLength(1));
    });

    test('"Bật" in Settings asks even before a machine is paired', () async {
      controller.start();
      await controller.requestFromSettings();
      expect(messaging.requests, 1);
      expect(backend.pushTokens, hasLength(1));
    });
  });

  group('token', () {
    test('signed in with permission: registered at launch, and again on onTokenRefresh', () async {
      messaging.current = PushPermission.granted;
      controller.start();
      await pumpEventQueue();
      expect(backend.pushTokens, [('fcm-1', PushPlatform.ios)]);

      messaging.refreshes.add('fcm-2');
      await pumpEventQueue();
      expect(backend.pushTokens.last, ('fcm-2', PushPlatform.ios));
    });

    test('a failed registration (offline, an old relay) is retried on the next sign-in', () async {
      messaging.current = PushPermission.granted;
      backend.pushTokenError = const ApiException(status: 404, code: 'not_found', message: 'no');
      controller.start();
      await pumpEventQueue();
      expect(backend.pushTokens, hasLength(1));

      session.signOut();
      await pumpEventQueue();
      final next = FakeBackend();
      session.signIn(next);
      await pumpEventQueue();
      expect(next.pushTokens, hasLength(1));
    });

    test('no token yet (iOS before APNs): nothing is sent, the refresh brings it', () async {
      messaging.current = PushPermission.granted;
      messaging.tokenValue = null;
      controller.start();
      await pumpEventQueue();
      expect(backend.pushTokens, isEmpty);
      messaging.refreshes.add('fcm-late');
      await pumpEventQueue();
      expect(backend.pushTokens, [('fcm-late', PushPlatform.ios)]);
    });

    test('signed out: no registration, and the install token is deleted', () async {
      messaging.current = PushPermission.granted;
      controller.start();
      await pumpEventQueue();
      session.signOut(SignOutReason.loggedOut);
      await pumpEventQueue();
      expect(messaging.deletes, 1);

      messaging.refreshes.add('fcm-2');
      controller.onPairedMachines(1);
      await pumpEventQueue();
      expect(backend.pushTokens, hasLength(1));
    });

    test('turned off in the system settings after a registration: the install token is deleted '
        'once', () async {
      messaging.current = PushPermission.granted;
      controller.start();
      await pumpEventQueue();
      expect(prefs.getBool(PushController.registeredKey), isTrue);

      messaging.current = PushPermission.denied;
      await controller.refreshPermission();
      expect(messaging.deletes, 1);
      expect(prefs.getBool(PushController.registeredKey), isFalse);
      await controller.refreshPermission();
      expect(messaging.deletes, 1);

      // Turned on again: a new registration.
      messaging.current = PushPermission.granted;
      await controller.refreshPermission();
      expect(backend.pushTokens, hasLength(2));
    });

    test('turned off in the system settings: the relay also forgets the token', () async {
      messaging.current = PushPermission.granted;
      controller.start();
      await pumpEventQueue();
      messaging.current = PushPermission.denied;
      await controller.refreshPermission();
      expect(backend.pushTokenDeletes, 1);
      expect(messaging.deletes, 1);
    });

    test('a sign-out whose token deletion did not happen is retried at the next start', () async {
      await prefs.setBool(PushController.registeredKey, true);
      session.signOut(SignOutReason.loggedOut);
      controller.start();
      await pumpEventQueue();
      expect(messaging.deletes, 1);
      expect(prefs.getBool(PushController.registeredKey), isFalse);
    });

    test('account A → account B: A\'s token is deleted first, then B registers a fresh one', () async {
      messaging.current = PushPermission.granted;
      controller.start();
      await pumpEventQueue();
      expect(backend.pushTokens, [('fcm-1', PushPlatform.ios)]);

      final order = <String>[];
      final next = FakeBackend();
      messaging.onDelete = () {
        order.add('delete');
        messaging.tokenValue = 'fcm-2';
      };
      session.signIn(next);
      await pumpEventQueue();
      order.add('register ${next.pushTokens.single.$1}');
      expect(order, ['delete', 'register fcm-2']);
      expect(backend.pushTokens, hasLength(1));
    });

    test('a registration that completes after a sign-out does not mark the token registered', () async {
      messaging.current = PushPermission.granted;
      final gate = Completer<void>();
      backend.pushTokenGate = gate;
      controller.start();
      await pumpEventQueue();
      session.signOut(SignOutReason.loggedOut);
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();
      expect(prefs.getBool(PushController.registeredKey), isNot(isTrue));
    });

    test('Firebase missing: nothing is asked, registered or listened to', () async {
      messaging = FakePushMessaging(available: false);
      controller = build()..start();
      controller.onPairedMachines(1);
      await pumpEventQueue();
      expect(controller.available, isFalse);
      expect(messaging.requests, 0);
      expect(backend.pushTokens, isEmpty);
      expect(messaging.foreground.hasListener, isFalse);
      expect(await controller.refreshPermission(), isNull);
    });
  });

  group('messages', () {
    test('in the foreground: a banner with title and body; tapping it opens the message', () async {
      controller.start();
      messaging.foreground.add(message);
      expect(popup.infos, ['MacBook · Phiên 1']);
      expect(popup.infoDescriptions, ['✓ npm test · 3 phút 12 giây']);

      popup.infoCallbacks.single.onTap!(
        ToastificationItem(builder: (_, _) => const SizedBox(), alignment: Alignment.topCenter),
      );
      expect(opener.opened, [message]);
    });

    test('no banner over the app lock', () async {
      lockEnabled = true;
      lock.lockOnLaunch();
      controller.start();
      messaging.foreground.add(message);
      expect(popup.infos, isEmpty);
    });

    test('a tapped notification, and the one that launched the app, are opened', () async {
      messaging.initial = message;
      controller.start();
      await pumpEventQueue();
      expect(opener.opened, [message]);

      messaging.opened.add(message);
      await pumpEventQueue();
      expect(opener.opened, hasLength(2));
    });
  });

  group('the buttons of an AI permission push (V2-2b B10)', () {
    const data = {
      'kind': 'ai',
      'ai_session': 'k3f9za.-12',
      'agent_id': agentA,
      'perm': '41',
      'allow': 'allow-once',
      'reject': 'reject-once',
    };
    const allow = PushMessage(
      title: 'MacBook · Claude',
      body: 'Cần bạn trả lời: Sửa src/main.ts',
      data: data,
      action: 'allow',
    );
    late RecordingAnswerer answerer;

    setUp(() {
      answerer = RecordingAnswerer();
      controller.dispose();
      controller = PushController(
        messaging: messaging,
        session: session,
        prefs: prefs,
        opener: opener,
        device: const DeviceDescription(name: 'iPhone 15', platform: DevicePlatform.ios),
        lock: lock,
        popup: () => popup,
        answerer: answerer,
      );
    });

    test('a button that launched the app, and one tapped later, go to the answerer, not the opener', () async {
      messaging.initial = allow;
      controller.start();
      await pumpEventQueue();
      messaging.opened.add(const PushMessage(data: data, action: 'reject'));
      await pumpEventQueue();
      expect([for (final (_, a) in answerer.answered) a.option], ['allow-once', 'reject-once']);
      expect(opener.opened, isEmpty);
    });

    test('the notification itself, a banner, or a button whose data does not read right only opens', () async {
      controller.start();
      const body = PushMessage(title: 'MacBook · Claude', data: data);
      final bad = PushMessage(data: {...data, 'perm': 'x'}, action: 'allow');
      messaging.opened
        ..add(body)
        ..add(bad);
      await pumpEventQueue();
      expect(answerer.answered, isEmpty);
      expect(opener.opened, [body, bad]);
    });

    test('without an answerer (an older wiring) a button opens like a tap', () async {
      controller.dispose();
      controller = build()..start();
      messaging.opened.add(allow);
      await pumpEventQueue();
      expect(opener.opened, [allow]);
    });
  });
}
