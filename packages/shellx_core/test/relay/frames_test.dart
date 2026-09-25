import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_core/src/util/cbor_values.dart';
import 'package:test/test.dart';

const _peer = '0f8fad5b-d9cb-469f-a165-70867728950e';
const _peerHex = '0f8fad5bd9cb469fa16570867728950e';

Uint8List _hex(String hex) => hexToBytes(hex);

void main() {
  group('ChannelId', () {
    test('requires exactly 8 bytes and copies them', () {
      final source = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final id = ChannelId(source);
      source[0] = 99;
      expect(id.bytes.first, 1);
      expect(() => ChannelId(Uint8List(7)), throwsArgumentError);
      expect(() => ChannelId(Uint8List(9)), throwsArgumentError);
    });

    test('equality and hashCode follow content; toString is 16 hex chars', () {
      final a = ChannelId(_hex('0102030405060708'));
      final b = ChannelId(_hex('0102030405060708'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), '0102030405060708');
      expect(ChannelId.zero.toString(), '0000000000000000');
    });

    test('random uses the given Random and differs between calls', () {
      expect(ChannelId.random(Random(1)), ChannelId.random(Random(1)));
      expect(ChannelId.random(), isNot(ChannelId.random()));
    });

    test(
      'bytes is unmodifiable, so it cannot be used to corrupt ChannelId.zero',
      () {
        final id = ChannelId(_hex('0102030405060708'));
        expect(() => id.bytes[0] = 99, throwsUnsupportedError);
        expect(() => ChannelId.zero.bytes[0] = 7, throwsUnsupportedError);
        expect(ChannelId.zero.bytes, Uint8List(8));
      },
    );
  });

  group('RelayFrame golden bytes (must match relay/ byte-for-byte)', () {
    test('DATA', () {
      final frame = DataFrame(
        peer: _peer,
        channel: ChannelId(_hex('0102030405060708')),
        payload: _hex('04aa'),
      );
      final wire = '0101${_peerHex}010203040506070804aa';
      expect(bytesToHex(frame.encode()), wire);
      expect(RelayFrame.decode(_hex(wire)), frame);
    });

    test('DATA with empty payload is 26 bytes', () {
      final frame = DataFrame(
        peer: _peer,
        channel: ChannelId.zero,
        payload: Uint8List(0),
      );
      expect(frame.encode(), hasLength(kDataFrameHeaderBytes));
      expect(RelayFrame.decode(frame.encode()), frame);
    });

    test('PRESENCE online and offline', () {
      expect(
        bytesToHex(const PresenceFrame(deviceId: _peer, online: true).encode()),
        '0102${_peerHex}01',
      );
      expect(
        RelayFrame.decode(_hex('0102${_peerHex}00')),
        const PresenceFrame(deviceId: _peer, online: false),
      );
    });

    test('ERROR with peer and channel', () {
      final frame = ErrorFrame(
        code: RelayErrorCode.peerOffline,
        deviceId: _peer,
        channel: ChannelId(_hex('a1a2a3a4a5a6a7a8')),
      );
      final wire = '01030001${_peerHex}a1a2a3a4a5a6a7a8';
      expect(bytesToHex(frame.encode()), wire);
      expect(RelayFrame.decode(_hex(wire)), frame);
    });

    test('ERROR without peer uses nil uuid and zero channel', () {
      final frame = ErrorFrame(code: RelayErrorCode.rateLimited);
      expect(frame.deviceId, nilUuid);
      expect(frame.channel, ChannelId.zero);
      expect(bytesToHex(frame.encode()), '01030003${'00' * 16}${'00' * 8}');
    });

    test('EVENT decodes a minimal CBOR map built like the relay builds it', () {
      final agent = '11111111-2222-3333-4444-555555555555';
      final mobile = '66666666-7777-8888-9999-aaaaaaaaaaaa';
      final body = BytesBuilder()
        ..addByte(0xa3) // map(3)
        ..addByte(0x65) // text(5)
        ..add(utf8.encode('event'))
        ..addByte(0x6f) // text(15)
        ..add(utf8.encode('pairing_removed'))
        ..addByte(0x68) // text(8)
        ..add(utf8.encode('agent_id'))
        ..add([0x78, 36]) // text(36), 1-byte length
        ..add(utf8.encode(agent))
        ..addByte(0x69) // text(9)
        ..add(utf8.encode('mobile_id'))
        ..add([0x78, 36])
        ..add(utf8.encode(mobile));
      final wire = Uint8List.fromList([1, 4, ...body.takeBytes()]);
      final expected = EventFrame({
        'event': 'pairing_removed',
        'agent_id': agent,
        'mobile_id': mobile,
      });
      expect(RelayFrame.decode(wire), expected);
      expect(RelayFrame.decode(expected.encode()), expected);
    });
  });

  group('RelayFrame.decode rejects malformed frames', () {
    final cases = <String, String>{
      'empty': '',
      'only version': '01',
      'wrong version': '0201${_peerHex}0102030405060708',
      'unknown type': '0105',
      'DATA shorter than 26 bytes': '0101${_peerHex}01020304050607',
      'PRESENCE too short': '0102$_peerHex',
      'PRESENCE too long': '0102${_peerHex}0100',
      'PRESENCE bad flag': '0102${_peerHex}02',
      'ERROR unknown code': '01030009${'00' * 24}',
      'ERROR too short': '01030001${'00' * 23}',
      'EVENT not CBOR': '0104ff',
      'EVENT not a map': '010401',
      'EVENT non-text value': '0104a1616101',
    };
    cases.forEach((name, hex) {
      test(name, () {
        expect(
          () => RelayFrame.decode(_hex(hex)),
          throwsA(isA<FrameFormatException>()),
        );
      });
    });
  });

  test('RelayErrorCode wire values', () {
    expect(RelayErrorCode.values.map((c) => c.wire), [1, 2, 3, 4]);
    expect(RelayErrorCode.fromWire(4), RelayErrorCode.badFrame);
    expect(
      () => RelayErrorCode.fromWire(0),
      throwsA(isA<FrameFormatException>()),
    );
  });

  test('close codes and limits', () {
    expect(RelayCloseCode.replaced, 4001);
    expect(RelayCloseCode.revoked, 4002);
    expect(RelayCloseCode.rateLimited, 4003);
    expect(kMaxFrameBytes, 65536);
    expect(kRelayProtocolVersion, 1);
  });

  group('cbor_values', () {
    test('round-trips nested values with byte strings', () {
      final value = <Object?, Object?>{
        't': 'output',
        'n': 1790000000000,
        'neg': -1,
        'data': Uint8List.fromList([0, 255]),
        'list': <Object?>[true, null, 'x'],
      };
      final decoded = decodeCbor(encodeCbor(value)) as Map<Object?, Object?>;
      expect(decoded['t'], 'output');
      expect(decoded['n'], 1790000000000);
      expect(decoded['neg'], -1);
      expect(decoded['data'], isA<Uint8List>());
      expect(decoded['data'], [0, 255]);
      expect(decoded['list'], [true, null, 'x']);
    });

    test('encodes byte strings as CBOR major type 2', () {
      expect(bytesToHex(encodeCbor(Uint8List.fromList([1, 2]))), '420102');
    });

    test('rejects malformed input and floats', () {
      expect(() => decodeCbor(Uint8List(0)), throwsFormatException);
      expect(() => decodeCbor(_hex('8201')), throwsFormatException);
      expect(() => decodeCbor(_hex('ff')), throwsFormatException);
      expect(() => decodeCbor(_hex('f93c00')), throwsFormatException);
    });

    test('refuses to encode unsupported types', () {
      expect(() => encodeCbor(1.5), throwsArgumentError);
    });
  });

  group('cbor_values rejects excessive nesting (before decoding, not after)', () {
    /// `depth` nested one-element arrays, e.g. depth=2 -> `[[0]]`.
    Uint8List nestedArrays(int depth) {
      final builder = BytesBuilder();
      for (var i = 0; i < depth; i++) {
        builder.addByte(0x81); // array(1)
      }
      builder.addByte(0x00); // innermost item: unsigned int 0
      return builder.toBytes();
    }

    test(
      'decodeCbor rejects 10,000-deep nesting in well under a second '
      '(the recursive decode path takes ~1s of CPU and can stack-overflow)',
      () {
        final deep = nestedArrays(10000);
        final stopwatch = Stopwatch()..start();
        expect(() => decodeCbor(deep), throwsFormatException);
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(100),
          reason: 'must reject before ever calling the slow recursive decode',
        );
      },
    );

    test('decodeBatch rejects the same deep nesting quickly', () {
      final deep = nestedArrays(10000);
      final stopwatch = Stopwatch()..start();
      expect(() => decodeBatch(deep), throwsFormatException);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test(
      'Hs1Payload.decode and Hs2Payload.decode reject deep nesting quickly',
      () {
        final deep = nestedArrays(10000);
        final stopwatch = Stopwatch()..start();
        expect(() => Hs1Payload.decode(deep), throwsFormatException);
        expect(() => Hs2Payload.decode(deep), throwsFormatException);
        expect(stopwatch.elapsedMilliseconds, lessThan(200));
      },
    );

    test('RelayFrame.decode (EVENT) rejects deep nesting quickly instead of '
        'crashing the relay connection', () {
      final deep = Uint8List.fromList([1, 4, ...nestedArrays(10000)]);
      final stopwatch = Stopwatch()..start();
      expect(
        () => RelayFrame.decode(deep),
        throwsA(isA<FrameFormatException>()),
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test(
      'a legitimate depth-4 shape (array -> map -> array -> map) still decodes',
      () {
        const message = SessionListResult([
          SessionInfo(
            id: 1,
            index: 1,
            shell: 's',
            createdAt: 0,
            attached: true,
          ),
        ]);
        expect(decodeBatch(encodeBatch([message])), [message]);
      },
    );

    test('exactly 8 levels of nesting is still accepted', () {
      expect(decodeCbor(nestedArrays(8)), [
        [
          [
            [
              [
                [
                  [
                    [0],
                  ],
                ],
              ],
            ],
          ],
        ],
      ]);
    });

    test('values above int64 throw instead of silently saturating', () {
      // Major type 0 (unsigned int), additional info 27 (8-byte length),
      // value = 2^63 -- one past the largest representable signed int64.
      final bignum = _hex('1b8000000000000000');
      expect(() => decodeCbor(bignum), throwsFormatException);
    });
  });
}
