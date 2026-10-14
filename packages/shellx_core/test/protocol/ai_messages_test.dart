import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'frozen/messages_v1.dart' as v1;

Uint8List _json(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

/// V2-2 §4: the `ai.*` messages, and what every older peer does with them.
void main() {
  final body = _json({'v': 1});
  final samples = <AiMessage, Map<String, Object?>>{
    const AiList(): {'t': 'ai.list'},
    AiListResult(available: true, body: body): {
      't': 'ai.list.result',
      'available': true,
      'body': body,
    },
    const AiAttach(sid: 'e.1'): {'t': 'ai.attach', 'sid': 'e.1'},
    AiAttach(sid: 'e.1', body: body): {
      't': 'ai.attach',
      'sid': 'e.1',
      'body': body,
    },
    const AiDetach(sid: 'e.1'): {'t': 'ai.detach', 'sid': 'e.1'},
    const AiAck(sid: 'e.1', seq: 9): {'t': 'ai.ack', 'sid': 'e.1', 'seq': 9},
    const AiEarlier(sid: 'e.1', before: 40): {
      't': 'ai.earlier',
      'sid': 'e.1',
      'before': 40,
    },
    AiSnapshot(sid: 'e.1', seq: 1, body: body): {
      't': 'ai.snapshot',
      'sid': 'e.1',
      'seq': 1,
      'body': body,
    },
    AiUpdate(sid: 'e.1', seq: 2, body: body): {
      't': 'ai.update',
      'sid': 'e.1',
      'seq': 2,
      'body': body,
    },
    const AiClosed(sid: 'e.1', reason: 'gone'): {
      't': 'ai.closed',
      'sid': 'e.1',
      'reason': 'gone',
    },
    const AiPrompt(sid: 'e.1', rid: 3, text: 'Sửa lỗi'): {
      't': 'ai.prompt',
      'sid': 'e.1',
      'rid': 3,
      'text': 'Sửa lỗi',
    },
    const AiAnswer(sid: 'e.1', rid: 4, permission: 7, option: 'allow'): {
      't': 'ai.answer',
      'sid': 'e.1',
      'rid': 4,
      'permission': 7,
      'option': 'allow',
    },
    AiAnswer(sid: 'e.1', rid: 5, ask: 2, action: 'accept', body: body): {
      't': 'ai.answer',
      'sid': 'e.1',
      'rid': 5,
      'ask': 2,
      'action': 'accept',
      'body': body,
    },
    const AiCancel(sid: 'e.1', rid: 6): {
      't': 'ai.cancel',
      'sid': 'e.1',
      'rid': 6,
    },
    const AiForceStop(sid: 'e.1', rid: 7): {
      't': 'ai.stop',
      'sid': 'e.1',
      'rid': 7,
    },
    const AiUnqueue(sid: 'e.1', rid: 8, queued: 11): {
      't': 'ai.unqueue',
      'sid': 'e.1',
      'rid': 8,
      'queued': 11,
    },
    const AiOpen(rid: 9, agent: 'claude', folder: 'ws:abc'): {
      't': 'ai.open',
      'rid': 9,
      'agent': 'claude',
      'folder': 'ws:abc',
    },
    const AiResult(rid: 9, ok: true, sid: 'e.4'): {
      't': 'ai.result',
      'rid': 9,
      'ok': true,
      'sid': 'e.4',
    },
    const AiResult(rid: 10, ok: false, code: 'stale'): {
      't': 'ai.result',
      'rid': 10,
      'ok': false,
      'code': 'stale',
    },
  };

  test('every ai.* message has the exact map and round-trips', () {
    for (final MapEntry(key: message, value: map) in samples.entries) {
      expect(message.toMap(), map, reason: message.type);
      expect(decodeBatch(encodeBatch([message])), [
        message,
      ], reason: message.type);
    }
  });

  test('toString never shows a prompt, a folder or a body', () {
    for (final message in samples.keys) {
      final text = message.toString();
      expect(text, isNot(contains('Sửa')));
      expect(text, isNot(contains('ws:abc')));
      expect(text, isNot(contains('bytes')));
      expect(text, endsWith('(…)'));
    }
  });

  test('a malformed or unknown ai.* message is skipped, never fatal', () {
    final bytes = encodeCbor([
      {'t': 'ack', 'id': 1, 'seq': 2},
      {'t': 'ai.prompt', 'sid': 5, 'rid': 1, 'text': 'x'}, // sid not a string
      {'t': 'ai.ack', 'sid': 'e.1'}, // seq missing
      {'t': 'ai.future', 'x': 1},
      {'t': 'session.reset', 'id': 1},
    ]);
    expect(decodeBatch(bytes), [
      const AckMessage(id: 1, seq: 2),
      const SessionReset(id: 1),
    ]);
  });

  test('a body of any depth stays one byte string (depth 3 on the wire)', () {
    var deep = <String, Object?>{'leaf': 1.5};
    for (var i = 0; i < 40; i++) {
      deep = {'n': deep};
    }
    final message = AiUpdate(sid: 'e.1', seq: 1, body: _json(deep));
    expect(decodeBatch(encodeBatch([message])), [message]);
  });

  test('the largest body fits one sealed batch with its envelope', () {
    final message = AiUpdate(
      sid: 'k3f9za.2147483647',
      seq: 1 << 40,
      body: Uint8List(kAiMaxBodyBytes),
    );
    expect(encodeBatch([message]).length, lessThan(kMaxSealedBatchBytes));
  });

  group('session.list.result carries the ai protocol (D3)', () {
    test('written only when set; read back', () {
      const without = SessionListResult([], desktopSharing: true);
      expect(without.toMap().containsKey('ai'), isFalse);
      const with1 = SessionListResult(
        [],
        desktopSharing: true,
        ai: kAiProtocol,
      );
      expect(with1.toMap()['ai'], 1);
      final decoded = decodeBatch(encodeBatch([with1])).single;
      expect((decoded as SessionListResult).ai, 1);
    });

    test('an older desktop sends none: null', () {
      final bytes = encodeCbor([
        {'t': 'session.list.result', 'sessions': [], 'desktop_sharing': true},
      ]);
      expect((decodeBatch(bytes).single as SessionListResult).ai, isNull);
    });
  });

  group(
    'compatibility with every released peer (frozen decoder at 5e04dc8)',
    () {
      test(
        'an old phone skips every ai.* message and keeps its neighbours',
        () {
          final bytes = encodeBatch([
            const AckMessage(id: 1, seq: 2),
            ...samples.keys,
            const SessionReset(id: 1),
          ]);
          final decoded = v1.decodeBatch(bytes);
          expect(decoded.map((m) => m.type), ['ack', 'session.reset']);
        },
      );

      test('an old phone reads session.list.result with ai as before', () {
        final bytes = encodeBatch([
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
          ),
        ]);
        final decoded = v1.decodeBatch(bytes).single as v1.SessionListResult;
        expect(decoded.sessions.single.id, 1);
        expect(decoded.desktopSharing, isTrue);
      });

      test('an old desktop skips what a new phone sends', () {
        final bytes = encodeBatch([
          const SessionList(desktop: true),
          const AiList(),
          const AiAttach(sid: 'e.1'),
          const AiPrompt(sid: 'e.1', rid: 1, text: 'x'),
        ]);
        expect(v1.decodeBatch(bytes).map((m) => m.type), ['session.list']);
      });
    },
  );
}
