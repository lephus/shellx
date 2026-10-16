import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

/// `term/protocol/vectors.txt`, written by the Rust side (plan P2a).
Map<String, String> _vectors() {
  final file = File('../../term/protocol/vectors.txt');
  return {
    for (final line in file.readAsLinesSync())
      if (line.isNotEmpty && !line.startsWith('#'))
        line.substring(0, line.indexOf('=')): line.substring(
          line.indexOf('=') + 1,
        ),
  };
}

Uint8List _fill(int byte, int length) =>
    Uint8List.fromList(List.filled(length, byte));

Uint8List _seq(int from, int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) from + i]);

void main() {
  final vectors = _vectors();

  group('byte-exact with vectors.txt', () {
    for (final name in vectors.keys.where((k) => k.startsWith('term.'))) {
      test('$name decodes and re-encodes to the same bytes', () {
        final bytes = hexToBytes(vectors[name]!);
        final message = TermToAgent.decode(bytes);
        expect(message, isNotNull);
        expect(bytesToHex(message!.encode()), vectors[name]);
      });
    }
    for (final name in vectors.keys.where((k) => k.startsWith('agent.'))) {
      test('$name decodes and re-encodes to the same bytes', () {
        final bytes = hexToBytes(vectors[name]!);
        final message = AgentToTerm.decode(bytes);
        expect(message, isNotNull);
        expect(bytesToHex(message!.encode()), vectors[name]);
      });
    }

    test('messages built from values encode to the vectors', () {
      expect(
        bytesToHex(TermHello(v: 1, nonce: _seq(1, 32)).encode()),
        vectors['term.hello'],
      );
      expect(
        bytesToHex(
          TermAuth(
            mac: _fill(0x55, 32),
            info: TermInfo(
              termId: _fill(0x11, 16),
              app: 'Terminal',
              shell: 'zsh',
              pid: 4242,
              cols: 80,
              rows: 24,
              startedAt: 1759276800000,
            ),
          ).encode(),
        ),
        vectors['term.auth'],
      );
      expect(
        bytesToHex(
          AgentChallenge(nonce: _seq(0x80, 32), mac: _fill(0x66, 32)).encode(),
        ),
        vectors['agent.challenge'],
      );
      expect(
        bytesToHex(const AgentReject(reason: AgentReject.limit).encode()),
        vectors['agent.reject_limit'],
      );
      expect(
        bytesToHex(
          AgentIn(data: Uint8List.fromList(utf8.encode('echo hi\r'))).encode(),
        ),
        vectors['agent.in'],
      );
      expect(
        bytesToHex(const AgentResize(cols: 50, rows: 20).encode()),
        vectors['agent.resize'],
      );
      expect(
        bytesToHex(const AgentLocalSize().encode()),
        vectors['agent.local_size'],
      );
      expect(bytesToHex(const AgentReady().encode()), vectors['agent.ready']);
    });

    test('decoded fields carry the values', () {
      final auth =
          TermToAgent.decode(hexToBytes(vectors['term.auth']!)) as TermAuth;
      expect(auth.info.app, 'Terminal');
      expect(auth.info.pid, 4242);
      expect(auth.info.startedAt, 1759276800000);
      expect(auth.info.key, '11' * 16);
      final out =
          TermToAgent.decode(hexToBytes(vectors['term.out']!)) as TermOut;
      expect(utf8.decode(out.data), 'tiếng Việt\r\n');
      final exit =
          TermToAgent.decode(hexToBytes(vectors['term.exit']!)) as TermExit;
      expect(exit.code, 130);
    });

    test('both proofs match auth.*_proof', () {
      final secret = hexToBytes(vectors['auth.secret']!);
      final nonceTerm = hexToBytes(vectors['auth.nonce_term']!);
      final nonceAgent = hexToBytes(vectors['auth.nonce_agent']!);
      expect(
        bytesToHex(agentProof(secret, nonceTerm, nonceAgent)),
        vectors['auth.agent_proof'],
      );
      expect(
        bytesToHex(termProof(secret, nonceAgent, nonceTerm)),
        vectors['auth.term_proof'],
      );
    });
  });

  test('hmacSha256 matches RFC 4231 test case 2', () {
    expect(
      bytesToHex(
        hmacSha256(
          utf8.encode('Jefe'),
          utf8.encode('what do ya want for nothing?'),
        ),
      ),
      '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    );
  });

  group('decode', () {
    Uint8List cbor(Map<String, Object?> map) => encodeCbor(map);

    test('an unknown t is null, not an error', () {
      expect(TermToAgent.decode(cbor({'t': 'future'})), isNull);
      expect(AgentToTerm.decode(cbor({'t': 'future'})), isNull);
    });

    test('keys in any order are accepted', () {
      final message = TermToAgent.decode(
        cbor({'v': 1, 't': 'hello', 'nonce': _seq(1, 32)}),
      );
      expect(message, isA<TermHello>());
    });

    final malformed = <String, Map<String, Object?>>{
      'no t': {'v': 1},
      'short nonce': {'t': 'hello', 'v': 1, 'nonce': _seq(1, 31)},
      'negative v': {'t': 'hello', 'v': -1, 'nonce': _seq(1, 32)},
      'zero cols': {'t': 'size', 'cols': 0, 'rows': 24},
      'cols over 65535': {'t': 'size', 'cols': 65536, 'rows': 24},
      'exit code over u32': {'t': 'exit', 'code': 1 << 32},
      'data not bytes': {'t': 'out', 'data': 'text'},
      'last not bool': {'t': 'snapshot', 'data': Uint8List(0), 'last': 1},
    };
    for (final MapEntry(:key, :value) in malformed.entries) {
      test('malformed: $key', () {
        expect(() => TermToAgent.decode(cbor(value)), throwsFormatException);
      });
    }

    test('not a map', () {
      expect(
        () => TermToAgent.decode(encodeCbor([1, 2])),
        throwsFormatException,
      );
      expect(
        () => TermToAgent.decode(Uint8List.fromList([0xff])),
        throwsFormatException,
      );
    });
  });

  group('frames', () {
    test('a frame is a 4-byte big-endian length and the payload', () {
      expect(termFrame(Uint8List.fromList([7, 8, 9])), [0, 0, 0, 3, 7, 8, 9]);
    });

    test('the reader splits a stream at any boundary', () {
      final payloads = [
        Uint8List.fromList([1]),
        Uint8List.fromList(List.filled(300, 2)),
        Uint8List(0),
      ];
      final stream = [for (final p in payloads) ...termFrame(p)];
      for (var cut = 0; cut <= stream.length; cut++) {
        final reader = TermFrameReader();
        final got = [
          ...reader.add(stream.sublist(0, cut)),
          ...reader.add(stream.sublist(cut)),
        ];
        expect(got, payloads, reason: 'cut at $cut');
      }
    });

    test('a length over 64 KiB is rejected before the payload arrives', () {
      final reader = TermFrameReader();
      expect(
        () => reader.add([0, 1, 0, 1]), // 65537
        throwsFormatException,
      );
    });

    test('termFrame refuses an oversized payload', () {
      expect(
        () => termFrame(Uint8List(kTermMaxFrame + 1)),
        throwsArgumentError,
      );
    });
  });

  test('toString never prints bytes', () {
    final secretish = _fill(0x42, 32);
    expect(
      '${TermHello(v: 1, nonce: secretish)}'
      '${AgentChallenge(nonce: secretish, mac: secretish)}'
      '${AgentIn(data: Uint8List.fromList(utf8.encode('password')))}',
      allOf(isNot(contains('42')), isNot(contains('password'))),
    );
  });
}
