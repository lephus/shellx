import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/notifications/data/android_push_actions.dart';
import 'package:shellx_mobile/features/notifications/domain/push_answer.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';

import '../../support/fakes.dart';

const Map<String, String> data = {
  'kind': 'ai',
  'ai_session': 'k3f9za.-12',
  'agent_id': agentA,
  'perm': '41',
  'allow': 'allow-once',
  'reject': 'reject-once',
};

const tag = 'ai-k3f9za--12-41';

AiActionNotification? note({Map<String, String> data = data, String? tag = tag}) => aiActionNotificationOf(
  data,
  title: 'MacBook · Claude',
  body: 'Cần bạn trả lời: Sửa src/main.ts',
  tag: tag,
);

/// V2-2b B9: what the background handler draws again, and what a tap on it brings back.
void main() {
  test('an AI permission push FCM drew with its tag gets buttons; anything else stays as FCM drew it', () {
    expect(note(), isNotNull);
    // An older relay draws it without a tag: drawing ours would show a second notification.
    expect(note(tag: null), isNull);
    expect(note(tag: 'FCM-Notification:1234'), isNull);
    expect(note(data: {...data, 'kind': 'command'}), isNull);
    expect(note(data: {...data}..remove('allow')), isNull);
    expect(note(data: {...data, 'perm': 'x'}), isNull);
    expect(note().toString(), 'AiActionNotification(…)');
  });

  test('each request is drawn under its own id, from its tag: stable, never 0, below 2^27 so that the request '
      'codes of its buttons (id * 16, id * 16 + 1) stay apart from every other one\'s and fit an int (F47)', () {
    // FNV-1a over the tag's UTF-8 bytes (values computed apart): the same id in any isolate, in any run.
    expect(note()!.id, 54036844);
    expect(
      [
        for (final t in ['ai-k3f9za--12-41', 'ai-k3f9za--12-42', 'ai-k3f9za--13-41', 'ai-k3f9zb--12-41'])
          aiActionIdOf(t),
      ],
      [54036844, 70814463, 55129777, 108346552],
    );
    final outside = [
      for (var pane = -50; pane < 50; pane++)
        for (var perm = 0; perm < 100; perm++)
          if (aiActionIdOf('ai-k3f9za-$pane-$perm') case final id when id < 1 || id >= 1 << 27) id,
    ];
    expect(outside, isEmpty);
  });

  test('drawn only in place of FCM\'s notification of the push, while it shows, under an id no notification has '
      '(F47)', () {
    final n = note()!;
    // FCM drew the push as (tag, 0): drawn, whatever else shows.
    expect(replacesFcmNotification(n, [(0, tag)]), isTrue);
    expect(
      replacesFcmNotification(n, [(0, 'ai-k3f9za--12-40'), (aiActionIdOf('ai-k3f9za--12-40'), null), (0, tag)]),
      isTrue,
    );
    // FCM's is gone (the user dismissed it) or not drawn: nothing is drawn, nothing is brought back.
    expect(replacesFcmNotification(n, []), isFalse);
    expect(replacesFcmNotification(n, [(0, 'ai-k3f9za--12-40'), (0, null), (7, tag), (null, tag)]), isFalse);
    // The id is taken (this push again, or another request whose tag hashes alike): never two notifications
    // with the same buttons.
    expect(replacesFcmNotification(n, [(0, tag), (n.id, null)]), isFalse);
    expect(replacesFcmNotification(n, [(n.id, 'ai-k3f9za--12-40'), (0, tag)]), isFalse);
  });

  test('"Từ chối" then "Cho phép", both opening the app, on the app\'s channel; without a tag (a button tap '
      'cancels it by its id) and silent (FCM\'s notification of the push already alerted)', () {
    final details = aiActionDetails(allow: 'Cho phép', reject: 'Từ chối').android!;
    expect(details.channelId, 'shellx_notifications');
    expect(details.tag, isNull);
    expect(details.silent, isTrue);
    expect(
      [for (final a in details.actions!) (a.id, a.title, a.showsUserInterface)],
      [
        ('reject', 'Từ chối', true),
        ('allow', 'Cho phép', true),
      ],
    );
  });

  group('the redraw (F47)', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    var active = <Map<String, Object?>>[];

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'getActiveNotifications' ? active : null;
      });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    Future<bool> redraw() =>
        redrawAiAction(FlutterLocalNotificationsPlugin(), note()!, allow: 'Cho phép', reject: 'Từ chối');

    test('the push is drawn under its own id, then FCM\'s notification of it is cancelled', () async {
      active = [
        {'id': 0, 'tag': tag},
      ];
      expect(await redraw(), isTrue);
      expect([for (final c in calls) c.method], ['getActiveNotifications', 'show', 'cancel']);
      final show = calls[1].arguments as Map<Object?, Object?>;
      final n = note()!;
      expect((show['id'], show['title'], show['body'], show['payload']), (n.id, n.title, n.body, n.payload));
      final details = show['platformSpecifics']! as Map<Object?, Object?>;
      expect((details['channelId'], details['tag'], details['silent']), ('shellx_notifications', null, true));
      expect(calls[2].arguments, {'id': 0, 'tag': tag});
    });

    test('nothing is drawn or cancelled when FCM\'s is gone or the id is taken', () async {
      for (final showing in [
        <Map<String, Object?>>[],
        [
          {'id': 0, 'tag': tag},
          {'id': note()!.id, 'tag': null},
        ],
      ]) {
        active = showing;
        calls.clear();
        expect(await redraw(), isFalse);
        expect([for (final c in calls) c.method], ['getActiveNotifications']);
      }
    });
  });

  test('a tap brings the push back, with the button that was pressed; a tap on its body has none', () {
    final payload = note()!.payload;
    final pressed = pushMessageOfResponse(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: 'allow',
        payload: payload,
      ),
    )!;
    expect(
      (pressed.title, pressed.body, pressed.action),
      ('MacBook · Claude', 'Cần bạn trả lời: Sửa src/main.ts', 'allow'),
    );
    expect(pressed.data, data);
    // The same answer as a button of an iOS push: B10 handles both alike.
    expect(PushAnswer.of(pressed)!.option, 'allow-once');
    final body = pushMessageOfResponse(
      NotificationResponse(notificationResponseType: NotificationResponseType.selectedNotification, payload: payload),
    )!;
    expect(body.action, isNull);
  });

  test('a payload that is not one of ours is no message', () {
    for (final payload in [null, '', 'x', '[]', '{}', '{"data": 3}']) {
      expect(pushMessageOfPayload(payload), isNull, reason: payload);
    }
    expect(pushMessageOfPayload(pushPayloadOf(const PushMessage(data: {'kind': 'ai'})))!.data, {'kind': 'ai'});
  });

  test('the channel is the one MainActivity creates and FCM draws on', () {
    final strings = File('android/app/src/main/res/values/strings.xml').readAsStringSync();
    expect(strings, contains('>$kPushChannelId<'));
  });
}
