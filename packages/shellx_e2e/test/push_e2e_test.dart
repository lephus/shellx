@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/e2e_world.dart';

final String? relayUrl = Platform.environment['SHELLX_E2E_RELAY'];

/// Port of the fake FCM server; the relay must have been started with
/// `FCM_ENDPOINT=http://127.0.0.1:<port>` and
/// `FCM_TOKEN_ENDPOINT=http://127.0.0.1:<port>/token` (relay/README.md,
/// "Push notifications").
final int fcmPort =
    int.tryParse(Platform.environment['SHELLX_E2E_FAKE_FCM_PORT'] ?? '') ??
    8788;

/// V2-2b B6: set to `1` when the relay runs from the `v2-2b-relay` branch: an
/// AI permission push then also carries the iOS category and the Android tag.
/// A relay without them still passes everything else on (the data included).
final bool expectActions =
    Platform.environment['SHELLX_E2E_EXPECT_ACTIONS'] == '1';

/// Plays Google: the OAuth token endpoint and FCM's `messages:send`.
final class FakeFcm {
  FakeFcm._(this._server) {
    _server.listen(_handle);
  }

  static Future<FakeFcm> start(int port) async =>
      FakeFcm._(await HttpServer.bind(InternetAddress.loopbackIPv4, port));

  final HttpServer _server;
  final messages = <Map<String, dynamic>>[];
  int tokenRequests = 0;

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/token') {
      tokenRequests++;
      request.response.write(
        jsonEncode({'access_token': 'fake-access', 'expires_in': 3600}),
      );
    } else if (request.uri.path.endsWith('/messages:send') &&
        request.headers.value('authorization') == 'Bearer fake-access') {
      messages.add(
        (jsonDecode(body) as Map<String, dynamic>)['message']
            as Map<String, dynamic>,
      );
      request.response.write(jsonEncode({'name': 'projects/p/messages/1'}));
    } else {
      request.response.statusCode = 404;
      request.response.write('{}');
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

final class _InteractiveZsh implements ShellResolver {
  const _InteractiveZsh();
  @override
  Future<ShellCommand> resolve() async => const ShellCommand(
    executable: '/bin/zsh',
    arguments: ['-i'],
    name: 'zsh',
  );
}

Uint8List keys(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test(
    'a ShellX session runs a command over the threshold: the fake FCM gets '
    'the paired phone\'s token, the title and the body',
    () async {
      final fcm = await FakeFcm.start(fcmPort);
      addTearDown(fcm.close);
      final temp = await Directory.systemTemp.createTemp('shellx-push-e2e-');
      addTearDown(() => temp.delete(recursive: true));
      final home = await Directory('${temp.path}/home').create();

      final world = await E2eWorld.create(
        Uri.parse(relayUrl!),
        shell: const _InteractiveZsh(),
        shellEnvironment: {
          'HOME': home.path,
          'PATH': '/usr/bin:/bin',
          'LANG': 'en_US.UTF-8',
        },
        shellIntegration: ShellIntegration(directory: '${temp.path}/hooks'),
        notifications: (api) => AgentNotifications(
          NotificationsConfig(
            api: api,
            threshold: () => const Duration(milliseconds: 500),
            machineName: () => 'e2e-agent',
            locale: () => 'vi_VN',
          ),
        ),
      );
      addTearDown(world.dispose);

      await world.pair(world.phone);
      await world.phone.api.registerPushToken(
        'fcm-token-of-e2e-phone',
        PushPlatform.android,
      );
      // The intruder (not paired) registers a token too: it must get nothing.
      await world.intruder.api.registerPushToken(
        'fcm-token-of-intruder',
        PushPlatform.ios,
      );

      final machine = world.phone.service.machine(world.agentId);
      await machine.connect();
      final tab = await machine.openSession(cols: 80, rows: 24);
      final output = TabText(tab);
      // Too short for the threshold: no notification for this one.
      machine.input(tab.id, keys('true\n'));
      machine.input(tab.id, keys('sleep 1; false\n'));
      await waitUntil(
        () => fcm.messages.isNotEmpty,
        timeout: const Duration(seconds: 20),
        reason:
            'the fake FCM got nothing (relay started with the FCM_* '
            'variables?); output: ${jsonEncode(output.text)}',
      );
      final message = fcm.messages.single;
      expect(message['token'], 'fcm-token-of-e2e-phone');
      expect(message['notification'], {
        'title': 'e2e-agent · Phiên 1',
        'body': '✗ sleep 1; false · mã 1 · 1 giây',
      });
      expect(message['data'], {
        'session_id': '${tab.id}',
        'kind': 'command',
        'agent_id': world.agentId,
      });
      expect(message['android'], {'priority': 'high'});

      // A message from a program (shellx notify) arrives without threshold.
      machine.input(tab.id, keys('shellx notify Build xong\n'));
      await waitUntil(() => fcm.messages.length == 2);
      expect(fcm.messages.last['notification'], {
        'title': 'e2e-agent · Phiên 1',
        'body': 'Build xong',
      });
      expect(fcm.messages.last['token'], 'fcm-token-of-e2e-phone');
    },
    skip: relayUrl == null
        ? 'Set SHELLX_E2E_RELAY=http://127.0.0.1:8787 and start the relay with '
              'the fake FCM variables (relay/README.md, "Push notifications")'
        : !File('/bin/zsh').existsSync()
        ? 'needs /bin/zsh'
        : null,
  );

  test(
    'an AI permission push carries its answers to the fake FCM: the request '
    'id and the two option ids in data and, through a relay of V2-2b, the '
    'iOS category and the Android tag (V2-2b B6, B7)',
    () async {
      final fcm = await FakeFcm.start(fcmPort);
      addTearDown(fcm.close);
      AgentNotifications? notices;
      final world = await E2eWorld.create(
        Uri.parse(relayUrl!),
        notifications: (api) => notices = AgentNotifications(
          NotificationsConfig(
            api: api,
            threshold: () => null,
            machineName: () => 'e2e-agent',
            locale: () => 'vi_VN',
          ),
        ),
      );
      addTearDown(world.dispose);
      await world.pair(world.phone);
      await world.phone.api.registerPushToken(
        'fcm-token-of-e2e-phone',
        PushPlatform.ios,
      );

      notices!.aiNotice(
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
      await waitUntil(
        () => fcm.messages.isNotEmpty,
        timeout: const Duration(seconds: 20),
        reason:
            'the fake FCM got nothing (relay started with the FCM_* '
            'variables?)',
      );
      final message = fcm.messages.single;
      expect(message['token'], 'fcm-token-of-e2e-phone');
      expect(message['notification'], {
        'title': 'e2e-agent · Claude',
        'body': 'Cần bạn trả lời: Sửa src/main.ts',
      });
      expect(message['data'], {
        'kind': 'ai',
        'ai_session': 'k3f9za.-12',
        'perm': '41',
        'allow': 'allow',
        'reject': 'reject',
        'agent_id': world.agentId,
      });
      if (expectActions) {
        expect(message['apns'], {
          'payload': {
            'aps': {'sound': 'default', 'category': 'ai_perm'},
          },
        });
        expect(message['android'], {
          'priority': 'high',
          'notification': {'tag': 'ai-k3f9za--12-41'},
        });
      }
    },
    skip: relayUrl == null
        ? 'Set SHELLX_E2E_RELAY=http://127.0.0.1:8787 and start the relay with '
              'the fake FCM variables (relay/README.md, "Push notifications")'
        : null,
  );
}
