import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_core/src/util/cbor_values.dart';
import 'package:test/test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  // One instance of every message type, with the exact CBOR map expected.
  final samples = <AppMessage, Map<String, Object?>>{
    const PairConfirm(): {'t': 'pair.confirm'},
    const SessionList(): {'t': 'session.list'},
    const SessionListResult([
      SessionInfo(
        id: 1,
        index: 1,
        shell: 'zsh',
        createdAt: 1790000000000,
        attached: true,
      ),
      SessionInfo(
        id: 7,
        index: 2,
        shell: 'pwsh',
        createdAt: 1790000000001,
        attached: false,
      ),
    ]): {
      't': 'session.list.result',
      'sessions': [
        {
          'id': 1,
          'index': 1,
          'shell': 'zsh',
          'created_at': 1790000000000,
          'attached': true,
        },
        {
          'id': 7,
          'index': 2,
          'shell': 'pwsh',
          'created_at': 1790000000001,
          'attached': false,
        },
      ],
    },
    const SessionOpen(cols: 80, rows: 24): {
      't': 'session.open',
      'cols': 80,
      'rows': 24,
    },
    const SessionOpened(id: 3, index: 2, shell: 'zsh'): {
      't': 'session.opened',
      'id': 3,
      'index': 2,
      'shell': 'zsh',
    },
    const SessionAttach(id: 3, cols: 100, rows: 30, lastSeq: 4096): {
      't': 'session.attach',
      'id': 3,
      'cols': 100,
      'rows': 30,
      'last_seq': 4096,
    },
    const SessionAttached(id: 3): {'t': 'session.attached', 'id': 3},
    const SessionReset(id: 3): {'t': 'session.reset', 'id': 3},
    OutputMessage(
      id: 3,
      seq: 5000000000,
      data: _bytes(utf8.encode('Xin chào 👋')),
    ): {
      't': 'output',
      'id': 3,
      'seq': 5000000000,
      'data': _bytes(utf8.encode('Xin chào 👋')),
    },
    const AckMessage(id: 3, seq: 32768): {'t': 'ack', 'id': 3, 'seq': 32768},
    InputMessage(id: 3, data: _bytes([0x1b, 0x5b, 0x41])): {
      't': 'input',
      'id': 3,
      'data': _bytes([0x1b, 0x5b, 0x41]),
    },
    const ResizeMessage(id: 3, cols: 120, rows: 40): {
      't': 'resize',
      'id': 3,
      'cols': 120,
      'rows': 40,
    },
    const SessionClose(id: 3): {'t': 'session.close', 'id': 3},
    const SessionExited(id: 3, exitCode: -1): {
      't': 'session.exited',
      'id': 3,
      'exit_code': -1,
    },
    const SessionDetached(id: 3, reason: DetachReason.takenOver): {
      't': 'session.detached',
      'id': 3,
      'reason': 'taken_over',
    },
    const SessionDetached(id: 4, reason: DetachReason.closedByHost): {
      't': 'session.detached',
      'id': 4,
      'reason': 'closed_by_host',
    },
    const ErrorMessage(code: AppErrorCode.sessionLimit, message: 'limit'): {
      't': 'error',
      'code': 'session_limit',
      'message': 'limit',
    },
    const ErrorMessage(
      code: AppErrorCode.sessionNotFound,
      message: 'gone',
      id: 9,
    ): {
      't': 'error',
      'code': 'session_not_found',
      'message': 'gone',
      'id': 9,
    },
    const ErrorMessage(
      code: AppErrorCode.spawnFailed,
      message: 'no shell',
      id: 2,
    ): {
      't': 'error',
      'code': 'spawn_failed',
      'message': 'no shell',
      'id': 2,
    },
    const SessionList(desktop: true): {'t': 'session.list', 'desktop': true},
    const SessionListResult([
      SessionInfo(
        id: 9,
        index: 1,
        shell: 'zsh',
        createdAt: 1790000000002,
        attached: false,
        kind: SessionKind.desktop,
        app: 'Terminal',
        title: 'npm run dev',
      ),
    ], desktopSharing: true): {
      't': 'session.list.result',
      'sessions': [
        {
          'id': 9,
          'index': 1,
          'shell': 'zsh',
          'created_at': 1790000000002,
          'attached': false,
          'kind': 'desktop',
          'app': 'Terminal',
          'title': 'npm run dev',
        },
      ],
      'desktop_sharing': true,
    },
    const SessionDetach(id: 9): {'t': 'session.detach', 'id': 9},
    const SessionDriver(id: 9, by: DriverSide.desktop): {
      't': 'session.driver',
      'id': 9,
      'by': 'desktop',
    },
    const SessionDetached(id: 9, reason: DetachReason.terminalGone): {
      't': 'session.detached',
      'id': 9,
      'reason': 'terminal_gone',
    },
  };

  group('toMap uses the wire keys', () {
    samples.forEach((message, expected) {
      test(message.type, () {
        expect(message.toMap(), expected);
        expect(message.type, expected['t']);
      });
    });
  });

  group('round trip through encodeBatch/decodeBatch', () {
    samples.forEach((message, _) {
      test(message.type, () {
        final decoded = decodeBatch(encodeBatch([message]));
        expect(decoded, hasLength(1));
        expect(decoded.single.runtimeType, message.runtimeType);
        expect(decoded.single, message);
        expect(decoded.single.toMap(), message.toMap());
      });
    });

    test('a batch keeps order', () {
      final batch = samples.keys.toList();
      expect(decodeBatch(encodeBatch(batch)), batch);
    });
  });

  test('data fields are CBOR byte strings (major type 2), not arrays', () {
    final encoded = encodeBatch([
      OutputMessage(id: 1, seq: 0, data: _bytes([0xde, 0xad])),
    ]);
    final hex = bytesToHex(encoded);
    expect(
      hex,
      contains(
        '6464617461'
        '42dead',
      ),
    ); // text "data" then bytes(2) de ad
    final input = encodeBatch([InputMessage(id: 1, data: Uint8List(0))]);
    expect(
      bytesToHex(input),
      contains(
        '6464617461'
        '40',
      ),
    ); // bytes(0)
  });

  test('empty data survives the round trip', () {
    final message = OutputMessage(id: 1, seq: 10, data: Uint8List(0));
    final decoded = decodeBatch(encodeBatch([message])).single as OutputMessage;
    expect(decoded.data, isEmpty);
  });

  test('unknown "t" is skipped, known neighbours are kept', () {
    final bytes = encodeCbor([
      {'t': 'session.attached', 'id': 1},
      {'t': 'future.feature', 'x': 1},
      {'t': 'session.reset', 'id': 2},
    ]);
    expect(decodeBatch(bytes), [
      const SessionAttached(id: 1),
      const SessionReset(id: 2),
    ]);
    expect(AppMessage.fromMap({'t': 'future.feature'}), isNull);
  });

  test('extra unknown keys in a known message are ignored', () {
    final bytes = encodeCbor([
      {'t': 'ack', 'id': 1, 'seq': 2, 'new_field': 'x'},
    ]);
    expect(decodeBatch(bytes), [const AckMessage(id: 1, seq: 2)]);
  });

  group('terminal sharing compatibility (spec §8)', () {
    test('session.list without desktop is byte-identical to before', () {
      expect(
        encodeBatch([const SessionList()]),
        encodeCbor([
          {'t': 'session.list'},
        ]),
      );
    });

    test('a shell SessionInfo and a result without desktop_sharing keep '
        'the old keys only', () {
      const result = SessionListResult([
        SessionInfo(
          id: 1,
          index: 1,
          shell: 'zsh',
          createdAt: 1,
          attached: false,
        ),
      ]);
      expect(result.toMap(), {
        't': 'session.list.result',
        'sessions': [
          {
            'id': 1,
            'index': 1,
            'shell': 'zsh',
            'created_at': 1,
            'attached': false,
          },
        ],
      });
    });

    test('missing desktop and desktop_sharing decode as false / null', () {
      final decoded = decodeBatch(
        encodeCbor([
          {'t': 'session.list'},
          {'t': 'session.list.result', 'sessions': <Object?>[]},
        ]),
      );
      expect((decoded[0] as SessionList).desktop, isFalse);
      expect((decoded[1] as SessionListResult).desktopSharing, isNull);
    });

    test('a session entry with an unknown kind is skipped, not an error', () {
      final decoded = decodeBatch(
        encodeCbor([
          {
            't': 'session.list.result',
            'sessions': [
              {
                'id': 1,
                'index': 1,
                'shell': 'zsh',
                'created_at': 1,
                'attached': false,
                'kind': 'hologram',
              },
              {
                'id': 2,
                'index': 1,
                'shell': 'zsh',
                'created_at': 1,
                'attached': false,
                'kind': 'desktop',
              },
            ],
          },
        ]),
      );
      final sessions = (decoded.single as SessionListResult).sessions;
      expect(sessions.map((s) => s.id), [2]);
      expect(sessions.single.kind, SessionKind.desktop);
      expect(sessions.single.app, '');
      expect(sessions.single.title, '');
    });

    test('DriverSide.fromWire rejects an unknown side', () {
      expect(DriverSide.fromWire('phone'), DriverSide.phone);
      expect(() => DriverSide.fromWire('tablet'), throwsFormatException);
    });
  });

  group('malformed input throws FormatException', () {
    final cases = <String, Object?>{
      'not an array': {'t': 'ack'},
      'item not a map': [1],
      'missing t': [
        <String, Object?>{'id': 1},
      ],
      't not a string': [
        <String, Object?>{'t': 1},
      ],
      'missing field': [
        <String, Object?>{'t': 'ack', 'id': 1},
      ],
      'wrong field type': [
        <String, Object?>{'t': 'output', 'id': 1, 'seq': 0, 'data': 'text'},
      ],
      'unknown detach reason': [
        <String, Object?>{'t': 'session.detached', 'id': 1, 'reason': 'x'},
      ],
      'unknown error code': [
        <String, Object?>{'t': 'error', 'code': 'x', 'message': 'm'},
      ],
      'error id not int': [
        <String, Object?>{
          't': 'error',
          'code': 'spawn_failed',
          'message': 'm',
          'id': 'a',
        },
      ],
      'session entry not a map': [
        <String, Object?>{
          't': 'session.list.result',
          'sessions': [1],
        },
      ],
      'session.driver with an unknown side': {
        't': 'session.driver',
        'id': 1,
        'by': 'tablet',
      },
      'session.detach without id': {'t': 'session.detach'},
      'session.list with a non-bool desktop': {
        't': 'session.list',
        'desktop': 1,
      },
      'session entry with a non-string kind': {
        't': 'session.list.result',
        'sessions': [
          {
            'id': 1,
            'index': 1,
            'shell': 'zsh',
            'created_at': 1,
            'attached': false,
            'kind': 7,
          },
        ],
      },
    };
    cases.forEach((name, value) {
      test(name, () {
        expect(() => decodeBatch(encodeCbor(value)), throwsFormatException);
      });
    });

    test('garbage bytes', () {
      expect(() => decodeBatch(_bytes([0xff, 0x00])), throwsFormatException);
    });
  });

  test('toString never prints terminal bytes', () {
    final message = InputMessage(
      id: 1,
      data: _bytes(utf8.encode('secret-password')),
    );
    expect(message.toString(), isNot(contains('secret')));
    expect(message.toString(), contains('<15 bytes>'));
  });

  group('handshake payloads', () {
    test('HS1 round trip and wire keys', () {
      final payload = Hs1Payload(
        proto: kAppProtocolVersion,
        app: '1.0.0',
        name: 'iPhone 15',
        platform: DevicePlatform.ios,
      );
      final decoded = Hs1Payload.decode(payload.encode());
      expect(decoded.proto, 1);
      expect(decoded.app, '1.0.0');
      expect(decoded.name, 'iPhone 15');
      expect(decoded.platform, DevicePlatform.ios);
      expect(decodeCbor(payload.encode()), {
        'proto': 1,
        'app': '1.0.0',
        'name': 'iPhone 15',
        'platform': 'ios',
      });
    });

    test('HS2 round trip for every status', () {
      for (final status in HandshakeStatus.values) {
        final payload = Hs2Payload(proto: 1, app: '1.0.0', status: status);
        final decoded = Hs2Payload.decode(payload.encode());
        expect(decoded.status, status);
        expect((decodeCbor(payload.encode()) as Map)['status'], status.wire);
      }
      expect(HandshakeStatus.values.map((s) => s.wire), [
        'ok',
        'untrusted',
        'pairing_invalid',
        'proto_unsupported',
      ]);
    });

    test('malformed payloads throw FormatException', () {
      expect(
        () => Hs1Payload.decode(encodeCbor({'proto': 1})),
        throwsFormatException,
      );
      expect(
        () => Hs1Payload.decode(
          encodeCbor({
            'proto': 1,
            'app': 'a',
            'name': 'n',
            'platform': 'linux',
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => Hs2Payload.decode(
          encodeCbor({'proto': 1, 'app': 'a', 'status': 'meh'}),
        ),
        throwsFormatException,
      );
      expect(() => Hs2Payload.decode(encodeCbor([1])), throwsFormatException);
      expect(() => Hs2Payload.decode(_bytes([0xff])), throwsFormatException);
    });

    test('enum wire helpers', () {
      expect(DevicePlatform.fromWire('windows'), DevicePlatform.windows);
      expect(DeviceKind.fromWire('agent'), DeviceKind.agent);
      expect(() => DeviceKind.fromWire('tablet'), throwsFormatException);
    });
  });
}
