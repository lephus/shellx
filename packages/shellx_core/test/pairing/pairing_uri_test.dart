import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

const _agentId = '0f8fad5b-d9cb-469f-a165-70867728950e';
final _key = Uint8List.fromList(List.generate(32, (i) => i));
final _secret = Uint8List.fromList(List.generate(32, (i) => 255 - i));
final _k = base64UrlNoPad(_key);
final _s = base64UrlNoPad(_secret);

void main() {
  test('toUriString has the exact spec format', () {
    final uri = PairingUri(
      agentDeviceId: _agentId,
      agentPublicKey: _key,
      secret: _secret,
    );
    expect(uri.toUriString(), 'shellx://pair?v=1&d=$_agentId&k=$_k&s=$_s');
    expect(_k, 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8');
    expect(_s, '__79_Pv6-fj39vX08_Lx8O_u7ezr6uno5-bl5OPi4eA');
    expect(_k, isNot(contains('=')));
  });

  test('parse round-trips', () {
    final parsed = PairingUri.parse(
      'shellx://pair?v=1&d=$_agentId&k=$_k&s=$_s',
    );
    expect(parsed.agentDeviceId, _agentId);
    expect(parsed.agentPublicKey, _key);
    expect(parsed.secret, _secret);
  });

  test(
    'parse tolerates whitespace, parameter order, trailing slash and uppercase uuid',
    () {
      final parsed = PairingUri.parse(
        '  shellx://pair/?s=$_s&k=$_k&d=${_agentId.toUpperCase()}&v=1\n',
      );
      expect(parsed.agentDeviceId, _agentId);
      expect(parsed.secret, _secret);
    },
  );

  group('parse rejects', () {
    final cases = <String, String>{
      'empty': '',
      'plain text': 'hello',
      'web url': 'https://shellx.pro/pair?v=1&d=$_agentId&k=$_k&s=$_s',
      'wrong scheme': 'shelly://pair?v=1&d=$_agentId&k=$_k&s=$_s',
      'wrong host': 'shellx://login?v=1&d=$_agentId&k=$_k&s=$_s',
      'extra path': 'shellx://pair/x?v=1&d=$_agentId&k=$_k&s=$_s',
      'missing version': 'shellx://pair?d=$_agentId&k=$_k&s=$_s',
      'future version': 'shellx://pair?v=2&d=$_agentId&k=$_k&s=$_s',
      'missing device': 'shellx://pair?v=1&k=$_k&s=$_s',
      'bad device': 'shellx://pair?v=1&d=not-a-uuid&k=$_k&s=$_s',
      'missing key': 'shellx://pair?v=1&d=$_agentId&s=$_s',
      'short key':
          'shellx://pair?v=1&d=$_agentId&k=${base64UrlNoPad(Uint8List(31))}&s=$_s',
      'long secret':
          'shellx://pair?v=1&d=$_agentId&k=$_k&s=${base64UrlNoPad(Uint8List(33))}',
      'standard base64 alphabet':
          'shellx://pair?v=1&d=$_agentId&k=$_k&s=${_s.replaceAll('_', '/')}',
      'missing secret': 'shellx://pair?v=1&d=$_agentId&k=$_k',
    };
    cases.forEach((name, input) {
      test(name, () {
        expect(() => PairingUri.parse(input), throwsFormatException);
      });
    });
  });

  test('constructor validates sizes', () {
    expect(
      () => PairingUri(
        agentDeviceId: _agentId,
        agentPublicKey: Uint8List(31),
        secret: _secret,
      ),
      throwsArgumentError,
    );
    expect(
      () =>
          PairingUri(agentDeviceId: 'x', agentPublicKey: _key, secret: _secret),
      throwsArgumentError,
    );
  });
}
