import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testUserId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const testDeviceId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

/// A scripted relay REST API (spec §10.2 shapes).
class FakeRelayHttp {
  String minMobile = '1.0.0';
  bool versionOffline = false;

  /// `GET /v1/version` answers only once this completes.
  Completer<void>? versionGate;
  Map<String, Object?>? loginError;

  /// `POST /v1/auth/login` and `/v1/auth/register` answer only once this completes.
  Completer<void>? loginGate;
  bool logoutOffline = false;

  /// `POST /v1/auth/logout` answers only once this completes (never, if it never does).
  Completer<void>? logoutGate;
  String accountPassword = 'correct horse';

  /// Runs when `DELETE /v1/account` deleted the account, before the response: the relay closes
  /// every socket with 4002 at that point.
  void Function()? onAccountDeleted;

  /// The account is deleted, but its response is lost (a network error instead of the 204).
  bool accountResponseLost = false;
  final List<http.Request> requests = [];

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/v1/version') {
      if (versionOffline) throw http.ClientException('offline');
      final gate = versionGate;
      if (gate != null) await gate.future;
      return http.Response(
        jsonEncode({
          'min_agent': '1.0.0',
          'min_mobile': minMobile,
          'latest_agent': {
            'version': '1.0.0',
            'mac_url': 'https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg',
            'win_url': 'https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe',
          },
        }),
        200,
      );
    }
    if (path == '/v1/auth/login' || path == '/v1/auth/register') {
      final gate = loginGate;
      if (gate != null) await gate.future;
      final error = loginError;
      if (error != null) return http.Response(jsonEncode({'error': error}), error['status'] as int);
      return http.Response(
        jsonEncode({'user_id': testUserId, 'device_id': testDeviceId, 'token': 'token-1'}),
        path.endsWith('register') ? 201 : 200,
      );
    }
    if (path == '/v1/account' && request.method == 'DELETE') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      if (body['password'] != accountPassword) {
        return http.Response(
          jsonEncode({
            'error': {'code': 'invalid_credentials', 'message': 'wrong password'},
          }),
          401,
        );
      }
      onAccountDeleted?.call();
      if (accountResponseLost) throw http.ClientException('connection reset');
      return http.Response('', 204);
    }
    if (path == '/v1/auth/logout') {
      if (logoutOffline) throw http.ClientException('offline');
      await logoutGate?.future;
      return http.Response('', 204);
    }
    return http.Response(
      jsonEncode({
        'error': {'code': 'not_found', 'message': path},
      }),
      404,
    );
  });

  http.Request lastTo(String path) => requests.lastWhere((r) => r.url.path == path);
}
