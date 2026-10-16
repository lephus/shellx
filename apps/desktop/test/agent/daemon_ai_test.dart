import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/daemon_ai.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';

import '../mux/mux_test_support.dart';
import '../support/fake_pty.dart';

/// V2-2 D1: what the background service does to serve phones' AI through the
/// attached window (`daemon_main.dart` calls it once, before it listens).
void main() {
  late List<http.Request> posts;

  SessionCore core({bool push = false}) => SessionCore(
    ptyFactory: FakePtyFactory(),
    shellResolver: const FixedShellResolver(),
    homeDirectory: '/Users/phu',
    baseEnvironment: const {'HOME': '/Users/phu'},
    api: ShellxApi(
      baseUri: Uri.parse('https://relay.test'),
      httpClient: MockClient((request) async {
        posts.add(request);
        return http.Response('{"sent":1}', 202);
      }),
    )..token = 'agent-token',
    notifications: push
        ? PushNotificationsSetup(
            threshold: () => null,
            machineName: () => 'MacBook-Pro',
            locale: () => 'vi_VN',
          )
        : null,
  );

  MuxServer serverOn(SessionCore c) => MuxServer(
    sessions: c.sessions,
    secret: testSecret,
    self: const MuxPeerInfo(protocol: kMuxProtocol, app: 't', instance: 'i'),
    onQuit: () async {},
  );

  setUp(() => posts = []);

  test('one forwarder is the server\'s and the slot\'s target', () {
    final c = core();
    final server = serverOn(c);
    expect(server.ai, isNull);
    expect(c.ai.target, isNull);

    final forwarder = installDaemonAi(server, c);

    expect(server.ai, same(forwarder));
    expect(c.ai.target, same(forwarder));
  });

  test('a push from the window goes out with the service\'s own '
      'notifications (its account, its limit)', () async {
    final c = core(push: true);
    final forwarder = installDaemonAi(serverOn(c), c);
    final window = Object();
    forwarder.serve(window, (_) {});

    forwarder.fromUi(
      window,
      MuxMessage(
        MuxType.aiPush,
        fields: const AiPush(
          kind: AiPushKind.needsInput,
          agentName: 'Claude',
          sid: 'e.-1',
          detail: 'Sửa src/main.ts',
        ).toFields(),
      ),
    );
    await c.notifications!.sender.idle;

    final post = posts.single;
    expect(post.url.path, '/v1/notifications');
    expect(post.headers['authorization'], 'Bearer agent-token');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['title'], 'MacBook-Pro · Claude');
    expect(body['data'], {'kind': 'ai', 'ai_session': 'e.-1'});
  });
}
