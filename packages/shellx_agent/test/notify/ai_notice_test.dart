import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

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
    });

    test('aiNotice sends title, body and the session to open', () {
      fakeAsync((async) {
        final bodies = <Map<String, dynamic>>[];
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
        final n = AgentNotifications(
          NotificationsConfig(
            api: api,
            threshold: () => null,
            machineName: () => 'MacBook',
            locale: () => 'vi_VN',
          ),
        );
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
  });
}
