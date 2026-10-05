import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/push_controller.dart';
import 'package:toastification/toastification.dart';

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
  late PushController controller;

  PushController build({DevicePlatform platform = DevicePlatform.ios}) => PushController(
    messaging: messaging,
    session: session,
    prefs: prefs,
    opener: opener,
    device: DeviceDescription(name: 'iPhone 15', platform: platform),
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
}
