import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

/// The notifications of machine "MacBook": what they ask the relay to send
/// lands in [bodies], decoded.
AgentNotifications notifications(
  List<Map<String, dynamic>> bodies, {
  String locale = 'vi_VN',
}) {
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
      locale: () => locale,
    ),
  );
}

/// V2-2 D11: the words and data of AI pushes.
void main() {
  group('push words (D11)', () {
    test('needs input and done, both languages', () {
      final vi = NotificationText('vi_VN');
      final en = NotificationText('en');
      expect(
        vi.aiNeedsInput('Sửa src/main.ts'),
        'Cần bạn trả lời: Sửa src/main.ts',
      );
      expect(vi.aiNeedsInput(null), 'Cần bạn trả lời');
      expect(
        en.aiNeedsInput('Run\nnpm test'),
        'Needs your answer: Run npm test',
      );
      expect(
        vi.aiDone(3, const Duration(minutes: 4, seconds: 2)),
        'Xong lượt 3 · 4 phút 2 giây',
      );
      expect(
        en.aiDone(3, const Duration(seconds: 45)),
        'Finished turn 3 · 45 s',
      );
      expect(vi.aiQuestion('Claude'), 'Claude hỏi bạn');
      expect(en.aiQuestion('Claude'), 'Claude has a question');
      expect(en.aiQuestion(' '), 'Needs your answer'); // no name to say
    });

    test('aiNotice sends title, body and the session to open', () {
      fakeAsync((async) {
        final bodies = <Map<String, dynamic>>[];
        final n = notifications(bodies);
        n.aiNotice(
          const AiPush(
            kind: AiPushKind.needsInput,
            agentName: 'Claude',
            sid: 'ep.-1',
            detail: 'Sửa src/main.ts',
          ),
        );
        async.flushMicrotasks();
        expect(bodies.single, {
          'title': 'MacBook · Claude',
          'body': 'Cần bạn trả lời: Sửa src/main.ts',
          'data': {'kind': 'ai', 'ai_session': 'ep.-1'},
        });
      });
    });

    test('a question pushes no word of the question, whatever the push '
        'holds (M2)', () {
      fakeAsync((async) {
        final bodies = <Map<String, dynamic>>[];
        final n = notifications(bodies, locale: 'en');
        n.aiNotice(
          const AiPush(
            kind: AiPushKind.needsInput,
            agentName: 'Claude',
            sid: 'ep.-1',
            question: true,
            detail: 'Paste the key from ~/.secrets/prod.env',
          ),
        );
        async.flushMicrotasks();
        expect(bodies.single['title'], 'MacBook · Claude');
        expect(bodies.single['body'], 'Claude has a question');
        expect(jsonEncode(bodies), isNot(contains('secrets')));
      });
    });

    test('from the hub to what the relay is asked: a question is "Claude '
        'has a question", a permission keeps its title (M2, N3)', () {
      fakeAsync((async) {
        final bodies = <Map<String, dynamic>>[];
        final n = notifications(bodies, locale: 'en');
        final rig = HubRig(sink: n.aiNotice);
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        final ask = s.addAsk(
          ElicitationRequest.fromJson({
            'mode': 'form',
            'message': 'Paste the key from ~/.secrets/prod.env',
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'key': {'type': 'string'},
              },
            },
          }),
        )!;
        async.flushMicrotasks();
        expect(bodies.single['body'], 'Claude has a question');
        expect(jsonEncode(bodies), isNot(contains('secrets')));

        s.resolveAsk(ask.id, const ElicitDecline());
        rig.now = rig.now.add(const Duration(minutes: 1));
        s.addPermission(
          PermissionRequest.fromJson({
            'sessionId': 's',
            'toolCall': {'toolCallId': 'c1', 'title': 'Run npm install'},
            'options': [
              {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
            ],
          }),
          aiT0,
        );
        async.flushMicrotasks();
        expect(bodies.last['body'], 'Needs your answer: Run npm install');
      });
    });
  });
}
