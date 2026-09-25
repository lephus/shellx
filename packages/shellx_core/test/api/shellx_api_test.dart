import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

/// Wraps a client so tests can observe whether [close] reached it.
final class _TrackingClient extends http.BaseClient {
  _TrackingClient(this._inner);
  final http.Client _inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}

const _userId = '0f8fad5b-d9cb-469f-a165-70867728950e';
const _deviceId = '11111111-2222-3333-4444-555555555555';
const _pairingId = 'c0ffee00-1234-7abc-9def-0123456789ab';

final _device = DeviceInfo(
  kind: DeviceKind.agent,
  name: 'MacBook-Pro',
  platform: DevicePlatform.macos,
  publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
);

http.Response _json(Object? body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _error(int status, String code, String message) => _json({
  'error': {'code': code, 'message': message},
}, status);

/// Records every request and answers with [handler].
final class _Recorder {
  _Recorder(this.handler);
  final FutureOr<http.Response> Function(http.Request request) handler;
  final requests = <http.Request>[];

  ShellxApi api({String base = 'https://relay.shellx.pro', String? token}) {
    return ShellxApi(
      baseUri: Uri.parse(base),
      httpClient: MockClient((request) async {
        requests.add(request);
        return handler(request);
      }),
    )..token = token;
  }

  http.Request get last => requests.single;
  Map<String, dynamic> get lastJson =>
      jsonDecode(last.body) as Map<String, dynamic>;
}

TypeMatcher<ApiException> _apiError(int status, String code) =>
    isA<ApiException>()
        .having((e) => e.status, 'status', status)
        .having((e) => e.code, 'code', code);

void main() {
  test('DeviceInfo.toJson uses wire names and unpadded base64url', () {
    expect(_device.toJson(), {
      'kind': 'agent',
      'name': 'MacBook-Pro',
      'platform': 'macos',
      'public_key': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
    });
  });

  group('register / login', () {
    for (final (name, path, status) in [
      ('register', '/v1/auth/register', 201),
      ('login', '/v1/auth/login', 200),
    ]) {
      test(
        '$name posts {email, password, device} and stores the token',
        () async {
          final recorder = _Recorder(
            (_) => _json({
              'user_id': _userId,
              'device_id': _deviceId,
              'token': 'tok-1',
            }, status),
          );
          final api = recorder.api();
          final result = name == 'register'
              ? await api.register('a@b.co', 'password1', _device)
              : await api.login('a@b.co', 'password1', _device);
          expect(recorder.last.method, 'POST');
          expect(recorder.last.url.toString(), 'https://relay.shellx.pro$path');
          expect(
            recorder.last.headers['content-type'],
            startsWith('application/json'),
          );
          expect(recorder.last.headers.containsKey('authorization'), isFalse);
          expect(recorder.lastJson, {
            'email': 'a@b.co',
            'password': 'password1',
            'device': _device.toJson(),
          });
          expect(result.userId, _userId);
          expect(result.deviceId, _deviceId);
          expect(result.token, 'tok-1');
          expect(api.token, 'tok-1');
        },
      );
    }

    test('maps relay errors', () async {
      final cases = <(int, String)>[
        (400, 'invalid_email'),
        (400, 'disposable_email'),
        (400, 'weak_password'),
        (409, 'email_taken'),
        (401, 'invalid_credentials'),
        (429, 'rate_limited'),
      ];
      for (final (status, code) in cases) {
        final api = _Recorder((_) => _error(status, code, 'msg $code')).api();
        await expectLater(
          api.login('a@b.co', 'x', _device),
          throwsA(
            _apiError(
              status,
              code,
            ).having((e) => e.message, 'message', 'msg $code'),
          ),
        );
        expect(api.token, isNull);
      }
    });
  });

  group('authenticated endpoints send the bearer token', () {
    test('logout posts and clears the token', () async {
      final recorder = _Recorder((_) => http.Response('', 204));
      final api = recorder.api(token: 'tok');
      await api.logout();
      expect(recorder.last.method, 'POST');
      expect(recorder.last.url.path, '/v1/auth/logout');
      expect(recorder.last.headers['authorization'], 'Bearer tok');
      expect(api.token, isNull);
    });

    test('logout clears the token even when the request fails', () async {
      final api = _Recorder(
        (_) => throw http.ClientException('offline'),
      ).api(token: 'tok');
      await expectLater(api.logout(), throwsA(_apiError(0, 'network')));
      expect(api.token, isNull);
    });

    test('a logout that completes late keeps a token set meanwhile', () async {
      final reply = Completer<http.Response>();
      final recorder = _Recorder((_) => reply.future);
      final api = recorder.api(token: 'A');
      final logout = api.logout();
      await pumpEventQueue();
      expect(recorder.last.headers['authorization'], 'Bearer A');

      // A new session signed in while the old logout was still in flight.
      api.token = 'B';
      reply.complete(http.Response('', 204));
      await logout;
      expect(api.token, 'B');
    });

    test('a late logout that fails keeps a token set meanwhile too', () async {
      final reply = Completer<http.Response>();
      final api = _Recorder((_) => reply.future).api(token: 'A');
      final logout = api.logout();
      await pumpEventQueue();
      api.token = 'B';
      reply.completeError(http.ClientException('offline'));
      await expectLater(logout, throwsA(_apiError(0, 'network')));
      expect(api.token, 'B');
    });

    test('changePassword posts new_password', () async {
      final recorder = _Recorder((_) => http.Response('', 204));
      await recorder.api(token: 'tok').changePassword('new-password');
      expect(recorder.last.url.path, '/v1/auth/password');
      expect(recorder.last.headers['authorization'], 'Bearer tok');
      expect(recorder.lastJson, {'new_password': 'new-password'});
    });

    test('changePassword maps agent_only', () async {
      final api = _Recorder(
        (_) => _error(403, 'agent_only', 'Agents only'),
      ).api(token: 'tok');
      await expectLater(
        api.changePassword('new-password'),
        throwsA(_apiError(403, 'agent_only')),
      );
    });

    test(
      'deleteAccount sends DELETE /v1/account with {password} and clears the token',
      () async {
        final recorder = _Recorder((_) => http.Response('', 204));
        final api = recorder.api(token: 'tok');
        await api.deleteAccount('password1');
        expect(recorder.last.method, 'DELETE');
        expect(
          recorder.last.url.toString(),
          'https://relay.shellx.pro/v1/account',
        );
        expect(recorder.last.headers['authorization'], 'Bearer tok');
        expect(
          recorder.last.headers['content-type'],
          startsWith('application/json'),
        );
        expect(recorder.lastJson, {'password': 'password1'});
        expect(api.token, isNull);
      },
    );

    test(
      'deleteAccount maps invalid_credentials and keeps the token',
      () async {
        final api = _Recorder(
          (_) => _error(401, 'invalid_credentials', 'Wrong password'),
        ).api(token: 'tok');
        await expectLater(
          api.deleteAccount('wrong'),
          throwsA(
            _apiError(
              401,
              'invalid_credentials',
            ).having((e) => e.message, 'message', 'Wrong password'),
          ),
        );
        expect(api.token, 'tok');
      },
    );

    test('devices parses the list', () async {
      final recorder = _Recorder(
        (_) => _json([
          {
            'id': _deviceId,
            'kind': 'agent',
            'name': 'MacBook-Pro',
            'platform': 'macos',
            'online': true,
            'last_seen_at': 1790000000000,
            'paired_with_me': false,
          },
          {
            'id': _userId,
            'kind': 'mobile',
            'name': 'iPhone',
            'platform': 'ios',
            'online': false,
            'last_seen_at': null,
            'paired_with_me': true,
          },
        ], 200),
      );
      final devices = await recorder.api(token: 'tok').devices();
      expect(recorder.last.method, 'GET');
      expect(recorder.last.url.path, '/v1/devices');
      expect(recorder.last.headers['authorization'], 'Bearer tok');
      expect(devices, hasLength(2));
      final agent = devices[0];
      expect(agent.id, _deviceId);
      expect(agent.kind, DeviceKind.agent);
      expect(agent.name, 'MacBook-Pro');
      expect(agent.platform, DevicePlatform.macos);
      expect(agent.online, isTrue);
      expect(agent.lastSeenAt, DateTime.utc(2026, 9, 21, 14, 13, 20));
      expect(agent.lastSeenAt!.millisecondsSinceEpoch, 1790000000000);
      expect(agent.pairedWithMe, isFalse);
      expect(devices[1].lastSeenAt, isNull);
      expect(devices[1].pairedWithMe, isTrue);
    });

    test('devices skips entries with an unknown kind or platform', () async {
      final api = _Recorder(
        (_) => _json([
          {
            'id': _deviceId,
            'kind': 'agent',
            'name': 'Linux box',
            'platform': 'linux',
            'online': true,
            'last_seen_at': null,
            'paired_with_me': false,
          },
          {
            'id': _userId,
            'kind': 'mobile',
            'name': 'Pixel',
            'platform': 'android',
            'online': true,
            'last_seen_at': null,
            'paired_with_me': true,
          },
        ], 200),
      ).api(token: 'tok');
      final devices = await api.devices();
      expect(devices.map((d) => d.name), ['Pixel']);
    });

    test('createPairing posts mobile_id and pairing_id', () async {
      final recorder = _Recorder((_) => http.Response('', 201));
      await recorder
          .api(token: 'tok')
          .createPairing(_userId, pairingId: _pairingId);
      expect(recorder.last.method, 'POST');
      expect(recorder.last.url.path, '/v1/pairings');
      expect(recorder.last.url.query, isEmpty);
      expect(recorder.last.headers['authorization'], 'Bearer tok');
      expect(recorder.lastJson, {
        'mobile_id': _userId,
        'pairing_id': _pairingId,
      });
    });

    test('createPairing maps device_not_found', () async {
      final api = _Recorder(
        (_) => _error(404, 'device_not_found', 'No such device'),
      ).api(token: 'tok');
      await expectLater(
        api.createPairing(_userId, pairingId: _pairingId),
        throwsA(_apiError(404, 'device_not_found')),
      );
    });

    test('createPairing maps 410 pairing_removed', () async {
      final api = _Recorder(
        (_) => _error(410, 'pairing_removed', 'Already removed'),
      ).api(token: 'tok');
      await expectLater(
        api.createPairing(_userId, pairingId: _pairingId),
        throwsA(
          _apiError(
            410,
            'pairing_removed',
          ).having((e) => e.message, 'message', 'Already removed'),
        ),
      );
    });

    test(
      'deletePairing sends DELETE /v1/pairings/:agent_id/:mobile_id',
      () async {
        final recorder = _Recorder((_) => http.Response('', 204));
        await recorder.api(token: 'tok').deletePairing(_deviceId, _userId);
        expect(recorder.last.method, 'DELETE');
        expect(recorder.last.url.path, '/v1/pairings/$_deviceId/$_userId');
        expect(recorder.last.url.hasQuery, isFalse);
        expect(recorder.last.headers['authorization'], 'Bearer tok');
      },
    );

    test('deletePairing with pairingId adds ?pairing_id=', () async {
      final recorder = _Recorder((_) => http.Response('', 204));
      await recorder
          .api(base: 'https://example.com/relay/', token: 'tok')
          .deletePairing(_deviceId, _userId, pairingId: _pairingId);
      expect(recorder.last.method, 'DELETE');
      expect(
        recorder.last.url.toString(),
        'https://example.com/relay/v1/pairings/$_deviceId/$_userId'
        '?pairing_id=$_pairingId',
      );
    });

    test('calls without a token fail locally with 401 unauthorized', () async {
      final recorder = _Recorder((_) => http.Response('', 204));
      final api = recorder.api();
      await expectLater(api.devices(), throwsA(_apiError(401, 'unauthorized')));
      await expectLater(
        api.changePassword('x'),
        throwsA(_apiError(401, 'unauthorized')),
      );
      await expectLater(
        api.deleteAccount('x'),
        throwsA(_apiError(401, 'unauthorized')),
      );
      expect(recorder.requests, isEmpty);
    });
  });

  group('version', () {
    test('is unauthenticated and parses latest_agent', () async {
      final recorder = _Recorder(
        (_) => _json({
          'min_agent': '1.0.0',
          'min_mobile': '1.0.1',
          'latest_agent': {
            'version': '1.2.0',
            'mac_url':
                'https://download.shellx.pro/desktop/1.2.0/ShellX-1.2.0.dmg',
            'win_url':
                'https://download.shellx.pro/desktop/1.2.0/ShellX-Setup-1.2.0.exe',
          },
        }, 200),
      );
      final info = await recorder.api(token: 'tok').version();
      expect(recorder.last.method, 'GET');
      expect(recorder.last.url.path, '/v1/version');
      expect(recorder.last.headers.containsKey('authorization'), isFalse);
      expect(info.minAgent, '1.0.0');
      expect(info.minMobile, '1.0.1');
      expect(info.latestAgent.version, '1.2.0');
      expect(info.latestAgent.macUrl.host, 'download.shellx.pro');
      expect(
        info.latestAgent.winUrl.path,
        '/desktop/1.2.0/ShellX-Setup-1.2.0.exe',
      );
    });
  });

  group('failure mapping', () {
    test('network errors become status 0, code "network"', () async {
      final api = _Recorder(
        (_) => throw http.ClientException('Connection refused'),
      ).api();
      await expectLater(
        api.version(),
        throwsA(
          _apiError(
            0,
            'network',
          ).having((e) => e.message, 'message', 'Connection refused'),
        ),
      );
    });

    test(
      'TLS handshake failures become status 0, code "network" '
      '(IOClient only wraps SocketException/HttpException, not TLS errors)',
      () async {
        final api = _Recorder(
          (_) => throw const HandshakeException('certificate verify failed'),
        ).api();
        await expectLater(api.version(), throwsA(_apiError(0, 'network')));
      },
    );

    test(
      'other TLS failures (TlsException) become status 0, code "network"',
      () async {
        final api = _Recorder((_) => throw const TlsException('x')).api();
        await expectLater(api.version(), throwsA(_apiError(0, 'network')));
      },
    );

    test('a request that never answers times out after 20 s as "network"', () {
      fakeAsync((async) {
        final api = _Recorder((_) => Completer<http.Response>().future).api();
        Object? error;
        api.version().then(
          (_) {},
          onError: (Object e) {
            error = e;
          },
        );
        async.elapse(const Duration(seconds: 19));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(error, _apiError(0, 'network'));
      });
    });

    test('non-JSON error bodies (proxy pages) become http_<status>', () async {
      final api = _Recorder(
        (_) => http.Response(
          '<html>Bad gateway</html>',
          502,
          reasonPhrase: 'Bad Gateway',
        ),
      ).api();
      await expectLater(
        api.version(),
        throwsA(
          _apiError(
            502,
            'http_502',
          ).having((e) => e.message, 'message', 'Bad Gateway'),
        ),
      );
    });

    test('429 without a JSON body keeps status 429', () async {
      final api = _Recorder((_) => http.Response('', 429)).api();
      await expectLater(
        api.login('a@b.co', 'x', _device),
        throwsA(_apiError(429, 'http_429')),
      );
    });

    test('malformed success bodies become bad_response', () async {
      final api = _Recorder(
        (_) => _json({'unexpected': true}, 200),
      ).api(token: 'tok');
      await expectLater(api.version(), throwsA(_apiError(200, 'bad_response')));
      await expectLater(api.devices(), throwsA(_apiError(200, 'bad_response')));
      final garbage = _Recorder((_) => http.Response('not json', 200)).api();
      await expectLater(
        garbage.version(),
        throwsA(_apiError(200, 'bad_response')),
      );
    });

    test(
      'a truncated success body never leaks response text into the message',
      () async {
        // jsonDecode's FormatException embeds a source excerpt around the
        // parse failure; a real truncated login/register reply would cut
        // off mid-token here.
        final api = _Recorder(
          (_) => http.Response('{"token": "SECRETTOKEN1234567890"', 200),
        ).api();
        Object? caught;
        try {
          await api.version();
        } catch (error) {
          caught = error;
        }
        expect(caught, isA<ApiException>());
        final error = caught! as ApiException;
        expect(error.message, isNot(contains('SECRET')));
        expect(error.status, 200);
        expect(error.code, 'bad_response');
      },
    );
  });

  group('close', () {
    test('closes a client it created itself without throwing', () {
      final api = ShellxApi(baseUri: Uri.parse('https://relay.shellx.pro'));
      expect(api.close, returnsNormally);
    });

    test('leaves an injected client open', () async {
      final tracking = _TrackingClient(
        MockClient(
          (_) async => _json({
            'min_agent': '1.0.0',
            'min_mobile': '1.0.0',
            'latest_agent': {
              'version': '1.0.0',
              'mac_url': 'https://x',
              'win_url': 'https://y',
            },
          }, 200),
        ),
      );
      final api = ShellxApi(
        baseUri: Uri.parse('https://relay.shellx.pro'),
        httpClient: tracking,
      );
      api.close();
      expect(tracking.closed, isFalse);
      // The client still works after close(), proving it was left open.
      await api.version();
    });
  });

  test('base URI with a path prefix and trailing slash is respected', () async {
    final recorder = _Recorder((_) => http.Response('', 204));
    await recorder.api(base: 'http://127.0.0.1:8787/', token: 't').logout();
    expect(
      recorder.last.url.toString(),
      'http://127.0.0.1:8787/v1/auth/logout',
    );
    final prefixed = _Recorder((_) => http.Response('', 204));
    await prefixed.api(base: 'https://example.com/relay', token: 't').logout();
    expect(
      prefixed.last.url.toString(),
      'https://example.com/relay/v1/auth/logout',
    );
  });
}
