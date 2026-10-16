import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'frozen/messages_v1.dart' as v1;
import 'frozen/messages_v2.dart' as v2;

Uint8List _json(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

/// V2-4 §4: the `tool.*` messages, and what every older peer does with them.
void main() {
  final body = _json({'v': 1});
  final bytes = Uint8List.fromList([1, 2, 3]);
  final samples = <ToolMessage, Map<String, Object?>>{
    const ToolList(): {'t': 'tool.list'},
    ToolListResult(available: true, body: body): {
      't': 'tool.list.result',
      'available': true,
      'body': body,
    },
    const ToolOpen(rid: 1, tool: 'k3f9za7q1m'): {
      't': 'tool.open',
      'rid': 1,
      'tool': 'k3f9za7q1m',
    },
    ToolOpened(rid: 1, ok: true, body: body): {
      't': 'tool.opened',
      'rid': 1,
      'ok': true,
      'body': body,
    },
    const ToolOpened(rid: 2, ok: false, code: 'refused'): {
      't': 'tool.opened',
      'rid': 2,
      'ok': false,
      'code': 'refused',
    },
    const ToolClose(tool: 'k3f9za7q1m'): {
      't': 'tool.close',
      'tool': 'k3f9za7q1m',
    },
    const ToolRequest(
      id: 7,
      tool: 'k3f9za7q1m',
      method: 'GET',
      target: '/src/main.ts?t=1',
      head: ['accept', '*/*', 'cookie', 'sid=Bảng'],
      end: true,
    ): {
      't': 'tool.req',
      'id': 7,
      'tool': 'k3f9za7q1m',
      'm': 'GET',
      'target': '/src/main.ts?t=1',
      'head': ['accept', '*/*', 'cookie', 'sid=Bảng'],
      'end': true,
    },
    const ToolRequest(
      id: 8,
      tool: 'k3f9za7q1m',
      method: 'GET',
      target: '/',
      head: [],
      alias: 49152,
      ws: true,
      end: true,
    ): {
      't': 'tool.req',
      'id': 8,
      'tool': 'k3f9za7q1m',
      'm': 'GET',
      'target': '/',
      'head': <String>[],
      'alias': 49152,
      'ws': true,
      'end': true,
    },
    const ToolResponse(
      id: 7,
      status: 200,
      head: ['content-type', 'text/html'],
      end: false,
    ): {
      't': 'tool.res',
      'id': 7,
      'status': 200,
      'head': ['content-type', 'text/html'],
      'end': false,
    },
    ToolData(id: 7, data: bytes, end: true): {
      't': 'tool.data',
      'id': 7,
      'data': bytes,
      'end': true,
    },
    const ToolAck([7, 65536, 8, 12]): {
      't': 'tool.ack',
      'acks': [7, 65536, 8, 12],
    },
    ToolWsMessage(id: 8, data: bytes, text: false, fin: true): {
      't': 'tool.ws.msg',
      'id': 8,
      'data': bytes,
      'text': false,
      'fin': true,
    },
    const ToolEnd(id: 7, code: 'disabled'): {
      't': 'tool.end',
      'id': 7,
      'code': 'disabled',
    },
    const ToolEnd(id: 8, wsCode: 1000, wsReason: 'bye'): {
      't': 'tool.end',
      'id': 8,
      'ws_code': 1000,
      'ws_reason': 'bye',
    },
  };

  test('every tool.* message has the exact map and round-trips', () {
    for (final MapEntry(key: message, value: map) in samples.entries) {
      expect(message.toMap(), map, reason: message.type);
      expect(decodeBatch(encodeBatch([message])), [
        message,
      ], reason: message.type);
    }
  });

  test('toString never shows a URL, a header or a body (E18)', () {
    for (final message in samples.keys) {
      final text = message.toString();
      expect(text, isNot(contains('main.ts')));
      expect(text, isNot(contains('cookie')));
      expect(text, isNot(contains('k3f9za7q1m')));
      expect(text, isNot(contains('bytes')));
      expect(text, '${message.runtimeType}(…)');
    }
  });

  test('a malformed or unknown tool.* message is skipped, never fatal', () {
    final batch = encodeCbor([
      {'t': 'ack', 'id': 1, 'seq': 2},
      {'t': 'tool.req', 'id': 'x', 'tool': 'a', 'm': 'GET', 'target': '/'},
      {
        't': 'tool.req',
        'id': 1,
        'tool': 'a',
        'm': 'GET',
        'target': '/',
        'head': ['only-a-name'], // odd: a name without its value
        'end': true,
      },
      {
        't': 'tool.res',
        'id': 1,
        'status': 200,
        'head': ['a', 5],
        'end': true,
      },
      {
        't': 'tool.ack',
        'acks': [1, 'x'],
      },
      {
        't': 'tool.ack',
        'acks': [1],
      },
      {'t': 'tool.data', 'id': 1, 'data': 'text, not bytes', 'end': true},
      {'t': 'tool.future', 'x': 1},
      {'t': 'session.reset', 'id': 1},
    ]);
    expect(decodeBatch(batch), [
      const AckMessage(id: 1, seq: 2),
      const SessionReset(id: 1),
    ]);
  });

  test('an end code this version does not know reads as aborted', () {
    expect(toolEndCode(null), isNull);
    expect(toolEndCode('refused'), 'refused');
    expect(toolEndCode('quota_exceeded'), 'aborted');
  });

  test('head bytes count UTF-8 (a Latin-1 byte above 0x7F takes two)', () {
    expect(toolHeadBytes(['ab', 'c']), 3);
    expect(toolHeadBytes(['é']), 2);
    expect(toolHeadBytes(['ả']), 3);
    expect(toolHeadBytes(['😀']), 4);
  });

  group('the largest message of each kind fits one sealed batch (RF 1)', () {
    // A head at the limit, made of many short pairs (the CBOR string headers
    // cost the most then) and of one long value (the other extreme).
    List<String> manyPairs() {
      final head = <String>[];
      var bytes = 0;
      var i = 0;
      while (head.length < kToolMaxHeaders * 2) {
        final name = 'h${i++}';
        final value = 'v' * 300;
        if (bytes + name.length + value.length > kToolMaxHeadBytes) break;
        head.addAll([name, value]);
        bytes += name.length + value.length;
      }
      return head;
    }

    final oneLong = ['cookie', 'ÿ' * ((kToolMaxHeadBytes - 6) ~/ 2)];
    const id = 0xFFFFFFFF;

    test('tool.req and tool.res', () {
      for (final head in [manyPairs(), oneLong]) {
        expect(toolHeadBytes(head), lessThanOrEqualTo(kToolMaxHeadBytes));
        final req = ToolRequest(
          id: id,
          tool: 'k' * 64,
          method: 'M' * kToolMaxMethodLength,
          target: '/${'x' * (kToolMaxTargetBytes - 1)}',
          head: head,
          alias: 65535,
          ws: true,
          end: false,
        );
        final res = ToolResponse(id: id, status: 999, head: head, end: false);
        expect(encodeBatch([req]).length, lessThan(kMaxSealedBatchBytes));
        expect(encodeBatch([res]).length, lessThan(kMaxSealedBatchBytes));
      }
    });

    test('tool.data, tool.ws.msg, tool.list.result and tool.opened', () {
      final full = Uint8List(kToolMaxChunkBytes);
      for (final message in <ToolMessage>[
        ToolData(id: id, data: full, end: true),
        ToolWsMessage(id: id, data: full, text: true, fin: true),
        ToolListResult(available: true, body: full),
        ToolOpened(rid: id, ok: true, code: 'unavailable', body: full),
      ]) {
        expect(
          encodeBatch([message]).length,
          lessThan(kMaxSealedBatchBytes),
          reason: message.type,
        );
      }
    });

    test('tool.ack for every stream a phone may hold, tool.end', () {
      final acks = [
        for (var i = 0; i < 48; i++) ...[id - i, 1 << 50],
      ];
      expect(
        encodeBatch([ToolAck(acks)]).length,
        lessThan(kMaxSealedBatchBytes),
      );
      final end = ToolEnd(
        id: id,
        code: 'desktop_closed',
        wsCode: 4999,
        wsReason: 'ả' * 41, // 123 UTF-8 bytes, a close frame's limit
      );
      expect(encodeBatch([end]).length, lessThan(kMaxSealedBatchBytes));
    });
  });

  group('session.list.result carries the tools protocol (E6)', () {
    test('written only when set; read back', () {
      const without = SessionListResult([], desktopSharing: true, ai: 1);
      expect(without.toMap().containsKey('tools'), isFalse);
      const with1 = SessionListResult(
        [],
        desktopSharing: true,
        ai: kAiProtocol,
        tools: kToolProtocol,
      );
      expect(with1.toMap()['tools'], 1);
      final decoded = decodeBatch(encodeBatch([with1])).single;
      expect((decoded as SessionListResult).tools, 1);
      expect(decoded.ai, kAiProtocol);
    });

    test('an older desktop sends none: null', () {
      final batch = encodeCbor([
        {'t': 'session.list.result', 'sessions': [], 'ai': 1},
      ]);
      expect((decodeBatch(batch).single as SessionListResult).tools, isNull);
    });
  });

  group('compatibility with every released peer (E19)', () {
    final neighbours = <AppMessage>[
      const AckMessage(id: 1, seq: 2),
      ...samples.keys,
      const AiList(),
      const SessionReset(id: 1),
    ];

    test('a V2-2 phone or desktop (frozen at d8ad686) skips every tool.* '
        'message and keeps its neighbours', () {
      final decoded = v2.decodeBatch(encodeBatch(neighbours));
      expect(decoded.map((m) => m.type), ['ack', 'ai.list', 'session.reset']);
    });

    test('a V1 peer (frozen at 5e04dc8) skips them too', () {
      final decoded = v1.decodeBatch(encodeBatch(neighbours));
      expect(decoded.map((m) => m.type), ['ack', 'session.reset']);
    });

    test('a V2-2 phone reads session.list.result with tools as before', () {
      final batch = encodeBatch([
        const SessionListResult(
          [
            SessionInfo(
              id: 1,
              index: 1,
              shell: 'zsh',
              createdAt: 1,
              attached: false,
            ),
          ],
          desktopSharing: true,
          ai: kAiProtocol,
          tools: kToolProtocol,
        ),
      ]);
      final decoded = v2.decodeBatch(batch).single as v2.SessionListResult;
      expect(decoded.sessions.single.id, 1);
      expect(decoded.ai, kAiProtocol);
      expect(decoded.desktopSharing, isTrue);
    });
  });
}
