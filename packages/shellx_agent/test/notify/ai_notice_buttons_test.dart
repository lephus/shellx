import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

/// The notifications of machine "MacBook": what they ask the relay to send
/// lands in [bodies], decoded.
AgentNotifications _notifications(List<Map<String, dynamic>> bodies) {
  final api = ShellxApi(
    baseUri: Uri.parse('https://relay.test'),
    httpClient: MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        '{"sent":1}',
        202,
        headers: {'content-type': 'application/json'},
      );
    }),
  )..token = 't';
  return AgentNotifications(
    NotificationsConfig(
      api: api,
      threshold: () => null,
      machineName: () => 'MacBook',
      locale: () => 'vi_VN',
    ),
  );
}

/// V2-2b B6, B7: what the relay is asked for a push with answer buttons.
void main() {
  test('a permission push with its answers asks for the buttons: perm, allow '
      'and reject in data, the ai_perm category and the request\'s tag', () {
    fakeAsync((async) {
      final bodies = <Map<String, dynamic>>[];
      _notifications(bodies).aiNotice(
        const AiPush(
          kind: AiPushKind.needsInput,
          agentName: 'Claude',
          sid: 'k3f9za.-12',
          detail: 'Sửa src/main.ts',
          permission: 41,
          allow: 'allow',
          reject: 'reject',
        ),
      );
      async.flushMicrotasks();
      expect(bodies.single, {
        'title': 'MacBook · Claude',
        'body': 'Cần bạn trả lời: Sửa src/main.ts',
        'data': {
          'kind': 'ai',
          'ai_session': 'k3f9za.-12',
          'perm': '41',
          'allow': 'allow',
          'reject': 'reject',
        },
        'category': 'ai_perm',
        'tag': 'ai-k3f9za--12-41',
      });
    });
  });

  test('a question, a finished turn and a push whose answers do not fit ask '
      'for no button and carry no answer', () {
    fakeAsync((async) {
      final bodies = <Map<String, dynamic>>[];
      _notifications(bodies)
        // A window never makes these two; the notice does not take its word.
        ..aiNotice(
          const AiPush(
            kind: AiPushKind.needsInput,
            agentName: 'Claude',
            sid: 'ep.-1',
            question: true,
            permission: 3,
            allow: 'a',
            reject: 'r',
          ),
        )
        ..aiNotice(
          const AiPush(
            kind: AiPushKind.done,
            agentName: 'Claude',
            sid: 'ep.-1',
            turn: 2,
            elapsed: Duration(seconds: 40),
            permission: 3,
            allow: 'a',
            reject: 'r',
          ),
        )
        ..aiNotice(
          AiPush(
            kind: AiPushKind.needsInput,
            agentName: 'Claude',
            sid: 'ep.-1',
            detail: 'Sửa a.ts',
            permission: 3,
            allow: 'a' * 257,
            reject: 'r',
          ),
        );
      async.flushMicrotasks();
      expect(bodies, hasLength(3));
      for (final body in bodies) {
        expect(body.containsKey('category'), isFalse);
        expect(body.containsKey('tag'), isFalse);
        expect(
          (body['data'] as Map<String, dynamic>).keys,
          unorderedEquals(['kind', 'ai_session']),
        );
      }
    });
  });
}
