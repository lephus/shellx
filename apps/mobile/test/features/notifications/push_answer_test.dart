import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/notifications/domain/push_answer.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';

import '../../support/fakes.dart';

/// What the desktop sends with a permission push that has buttons (V2-2b B7), the relay's `agent_id` included.
const Map<String, String> data = {
  'kind': 'ai',
  'ai_session': 'k3f9za.-12',
  'agent_id': agentA,
  'perm': '41',
  'allow': 'allow-once',
  'reject': 'reject-once',
};

PushMessage tap(String? action, {Map<String, String> data = data, String? body = 'Cần bạn trả lời: Sửa src/main.ts'}) =>
    PushMessage(title: 'MacBook · Claude', body: body, data: data, action: action);

/// V2-2b B10: which taps are answers, and what they answer.
void main() {
  test('"Cho phép" answers the allow option, "Từ chối" the reject option, of that request only', () {
    final allow = PushAnswer.of(tap('allow'))!;
    expect(
      (allow.agentId, allow.sid, allow.permission, allow.option, allow.allow, allow.task),
      (agentA, 'k3f9za.-12', 41, 'allow-once', true, 'Sửa src/main.ts'),
    );
    final reject = PushAnswer.of(tap('reject'))!;
    expect((reject.option, reject.allow), ('reject-once', false));
  });

  test('a tap on the notification itself, or on the system\'s own action, is no answer', () {
    expect(PushAnswer.of(tap(null)), isNull);
    expect(PushAnswer.of(tap('com.apple.UNNotificationDefaultActionIdentifier')), isNull);
    expect(PushAnswer.of(tap('allow_always')), isNull);
  });

  test('bad data sends nothing: data that is not exactly what the desktop sends is no answer', () {
    Map<String, String> without(String key) => {...data}..remove(key);
    for (final bad in [
      {...data, 'kind': 'command'},
      without('kind'),
      without('ai_session'),
      {...data, 'ai_session': ''},
      without('agent_id'),
      without('perm'),
      {...data, 'perm': 'x'},
      {...data, 'perm': '-1'},
      {...data, 'perm': '1.5'},
      {...data, 'perm': '+4'},
      {...data, 'perm': '1234567890123456'},
      without('allow'),
      without('reject'),
      {...data, 'allow': ''},
      {...data, 'reject': ''},
    ]) {
      expect(PushAnswer.of(tap('allow', data: bad)), isNull, reason: '$bad');
      expect(PushAnswer.of(tap('reject', data: bad)), isNull, reason: '$bad');
    }
  });

  test('R6: the request is the body without its head, in both languages; the whole body otherwise', () {
    expect(PushAnswer.taskOf('Cần bạn trả lời: Sửa src/main.ts'), 'Sửa src/main.ts');
    expect(PushAnswer.taskOf('Needs your answer: Run npm test'), 'Run npm test');
    expect(PushAnswer.taskOf('Cần bạn trả lời'), isNull);
    expect(PushAnswer.taskOf('Needs your answer:   '), isNull);
    expect(PushAnswer.taskOf('Something else'), 'Something else');
    expect(PushAnswer.taskOf(''), isNull);
    expect(PushAnswer.taskOf(null), isNull);
    expect(PushAnswer.of(tap('allow', body: null))!.task, isNull);
  });

  test('toString shows nothing of the request', () {
    final text = PushAnswer.of(tap('allow')).toString();
    expect(text, 'PushAnswer(…)');
  });
}
