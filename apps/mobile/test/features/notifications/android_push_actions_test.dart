import 'dart:io';

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

  test('"Từ chối" then "Cho phép", both opening the app; the push\'s tag, id 0 on the app\'s channel, one alert', () {
    final details = aiActionDetails(note()!, allow: 'Cho phép', reject: 'Từ chối').android!;
    expect(details.channelId, 'shellx_notifications');
    expect(details.tag, tag);
    expect(details.onlyAlertOnce, isTrue);
    expect(
      [for (final a in details.actions!) (a.id, a.title, a.showsUserInterface)],
      [
        ('reject', 'Từ chối', true),
        ('allow', 'Cho phép', true),
      ],
    );
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
