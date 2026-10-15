import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'frozen/messages_v1.dart' as v1;
import 'frozen/messages_v2.dart' as v2;

Uint8List _json(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

/// The plain maps [bytes] hold: what is on the wire.
List<Object?> _wire(Uint8List bytes) => decodeCbor(bytes)! as List<Object?>;

/// V2-2b §4 (B1, B2, B4): the messages V2-2b adds, the wire maps a forwarder
/// writes again, and what every older peer does with them.
void main() {
  final body = _json({'v': 1});
  final data = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1]);
  final samples = <AiMessage, Map<String, Object?>>{
    const AiConfigGet(sid: 'e.1', rid: 1): {
      't': 'ai.config.get',
      'sid': 'e.1',
      'rid': 1,
    },
    AiConfigSet(sid: 'e.1', rid: 2, body: body): {
      't': 'ai.config',
      'sid': 'e.1',
      'rid': 2,
      'body': body,
    },
    AiBlob(
      rid: 3,
      blob: 7,
      part: 0,
      parts: 2,
      mime: 'image/jpeg',
      data: data,
    ): {
      't': 'ai.blob',
      'rid': 3,
      'blob': 7,
      'part': 0,
      'parts': 2,
      'mime': 'image/jpeg',
      'data': data,
    },
    AiBlob(rid: 4, blob: 7, part: 1, parts: 2, data: data): {
      't': 'ai.blob',
      'rid': 4,
      'blob': 7,
      'part': 1,
      'parts': 2,
      'data': data,
    },
    const AiFiles(sid: 'e.1', rid: 5, query: 'sr'): {
      't': 'ai.files',
      'sid': 'e.1',
      'rid': 5,
      'q': 'sr',
    },
    const AiItemPart(sid: 'e.1', rid: 6, index: 12, part: 3): {
      't': 'ai.item',
      'sid': 'e.1',
      'rid': 6,
      'i': 12,
      'part': 3,
    },
    const AiHistory(sid: 'e.1', rid: 7): {
      't': 'ai.history',
      'sid': 'e.1',
      'rid': 7,
    },
    const AiHistory(sid: 'e.1', rid: 8, cursor: 'c2'): {
      't': 'ai.history',
      'sid': 'e.1',
      'rid': 8,
      'cursor': 'c2',
    },
    const AiFolder(sid: 'e.1', rid: 9, folder: 'ws:abc'): {
      't': 'ai.folder',
      'sid': 'e.1',
      'rid': 9,
      'folder': 'ws:abc',
    },
    const AiChanges(sid: 'e.1', rid: 10): {
      't': 'ai.changes',
      'sid': 'e.1',
      'rid': 10,
    },
    const AiChanges(sid: 'e.1', rid: 11, turn: 3): {
      't': 'ai.changes',
      'sid': 'e.1',
      'rid': 11,
      'turn': 3,
    },
    const AiDiff(sid: 'e.1', rid: 12, turn: 3, path: 'src/a.ts'): {
      't': 'ai.diff',
      'sid': 'e.1',
      'rid': 12,
      'turn': 3,
      'path': 'src/a.ts',
    },
    const AiDiff(sid: 'e.1', rid: 13, path: 'src/a.ts'): {
      't': 'ai.diff',
      'sid': 'e.1',
      'rid': 13,
      'path': 'src/a.ts',
    },
    const AiRevert(sid: 'e.1', rid: 14, turn: 3, keep: 'clean'): {
      't': 'ai.revert',
      'sid': 'e.1',
      'rid': 14,
      'turn': 3,
      'keep': 'clean',
    },
    const AiRevert(sid: 'e.1', rid: 15): {
      't': 'ai.revert',
      'sid': 'e.1',
      'rid': 15,
    },
    const AiPrompt(
      sid: 'e.1',
      rid: 16,
      text: 'Sửa lỗi',
      blobs: [7, 8],
      files: ['src/a.ts'],
    ): {
      't': 'ai.prompt',
      'sid': 'e.1',
      'rid': 16,
      'text': 'Sửa lỗi',
      'blobs': [7, 8],
      'files': ['src/a.ts'],
    },
    const AiOpen(rid: 17, agent: 'claude', folder: 'ws:abc', resume: 's-9'): {
      't': 'ai.open',
      'rid': 17,
      'agent': 'claude',
      'folder': 'ws:abc',
      'resume': 's-9',
    },
    AiResult(rid: 18, ok: false, code: 'confirm', body: body): {
      't': 'ai.result',
      'rid': 18,
      'ok': false,
      'code': 'confirm',
      'body': body,
    },
  };

  test('every V2-2b message has the exact map and round-trips', () {
    for (final MapEntry(key: message, value: map) in samples.entries) {
      expect(message.toMap(), map, reason: message.type);
      expect(message.wire, map, reason: 'made here: its fields');
      expect(decodeBatch(encodeBatch([message])), [
        message,
      ], reason: message.type);
    }
  });

  test('a V2-2a message keeps its exact V2-2a map when nothing new is set', () {
    expect(const AiPrompt(sid: 'e.1', rid: 1, text: 'x').toMap(), {
      't': 'ai.prompt',
      'sid': 'e.1',
      'rid': 1,
      'text': 'x',
    });
    expect(const AiOpen(rid: 2, agent: 'claude', folder: 'ws:a').toMap(), {
      't': 'ai.open',
      'rid': 2,
      'agent': 'claude',
      'folder': 'ws:a',
    });
    expect(const AiResult(rid: 3, ok: true).toMap(), {
      't': 'ai.result',
      'rid': 3,
      'ok': true,
    });
  });

  test(
    'toString never shows a query, a path, a folder, a prompt or a body',
    () {
      for (final message in samples.keys) {
        final text = message.toString();
        expect(text, '${message.runtimeType}(…)');
        for (final secret in ['sr', 'src/a.ts', 'ws:abc', 'Sửa', 'c2', 's-9']) {
          expect(text, isNot(contains(secret)));
        }
      }
    },
  );

  test('a malformed V2-2b message is skipped, never fatal', () {
    final bytes = encodeCbor([
      {'t': 'ack', 'id': 1, 'seq': 2},
      {'t': 'ai.blob', 'rid': 1, 'blob': 1, 'part': 0, 'parts': 1},
      {
        't': 'ai.blob',
        'rid': 1,
        'blob': 1,
        'part': 0,
        'parts': 1,
        'data': 'not bytes',
      },
      {
        't': 'ai.prompt',
        'sid': 'e.1',
        'rid': 2,
        'text': 'x',
        'blobs': ['7'],
      },
      {
        't': 'ai.prompt',
        'sid': 'e.1',
        'rid': 3,
        'text': 'x',
        'files': [1],
      },
      {'t': 'ai.item', 'sid': 'e.1', 'rid': 4, 'i': 'x', 'part': 0},
      {'t': 'ai.result', 'rid': 5, 'ok': true, 'body': 'x'},
      {'t': 'ai.config', 'sid': 'e.1', 'rid': 6},
      {'t': 'ai.open', 'rid': 7, 'agent': 'a', 'folder': 'f', 'resume': 3},
      {'t': 'session.reset', 'id': 1},
    ]);
    expect(decodeBatch(bytes), [
      const AckMessage(id: 1, seq: 2),
      const SessionReset(id: 1),
    ]);
  });

  group('a kind this version does not know (B2)', () {
    test('is an AiRaw that keeps the map it came as, its sid and rid when '
        'they have the right type', () {
      final bytes = encodeCbor([
        {
          't': 'ai.later',
          'sid': 'e.1',
          'rid': 4,
          'x': [
            1,
            {'y': true},
          ],
        },
        {'t': 'ai.other', 'sid': 5, 'rid': 'no'},
      ]);
      final [a, b] = decodeBatch(bytes);
      expect(a, isA<AiRaw>());
      a as AiRaw;
      expect((a.type, a.sid, a.rid), ('ai.later', 'e.1', 4));
      b as AiRaw;
      expect((b.type, b.sid, b.rid), ('ai.other', null, null));
      expect(_wire(encodeBatch([a, b])), _wire(bytes));
      expect(a.toString(), 'AiRaw(…)');
    });

    test('loses only keys that are no strings', () {
      final raw =
          decodeBatch(
                encodeCbor([
                  {'t': 'ai.later', 7: 'x', 'k': 1},
                ]),
              ).single
              as AiRaw;
      expect(raw.wire, {'t': 'ai.later', 'k': 1});
    });
  });

  test('a known kind keeps what this version does not know when it is '
      'written again (B2): a forwarder passes on what a newer peer said', () {
    final bytes = encodeCbor([
      {'t': 'ai.result', 'rid': 1, 'ok': true, 'later': 'x'},
      {'t': 'ai.prompt', 'sid': 'e.1', 'rid': 2, 'text': 'hi', 'tone': 'calm'},
    ]);
    final decoded = decodeBatch(bytes);
    expect(decoded, [
      const AiResult(rid: 1, ok: true),
      const AiPrompt(sid: 'e.1', rid: 2, text: 'hi'),
    ], reason: 'its fields are what this version reads');
    expect(_wire(encodeBatch(decoded)), _wire(bytes));
  });

  test('the constant AiList is never given a wire map by a decode', () {
    decodeBatch(
      encodeCbor([
        {'t': 'ai.list', 'extra': 1},
      ]),
    );
    expect(const AiList().wire, {'t': 'ai.list'});
    expect(_wire(encodeBatch([const AiList()])), [
      {'t': 'ai.list'},
    ]);
  });

  test('the largest of each V2-2b message fits one sealed batch with its '
      'envelope', () {
    const sid = 'k3f9za.-2147483648';
    final largest = <AiMessage>[
      AiBlob(
        rid: 1 << 40,
        blob: 1 << 40,
        part: 1 << 20,
        parts: 1 << 20,
        mime: 'image/jpeg',
        data: Uint8List(kAiMaxBlobPartBytes),
      ),
      AiResult(
        rid: 1 << 40,
        ok: false,
        code: 'confirm',
        sid: sid,
        body: Uint8List(kAiMaxBodyBytes),
      ),
      AiConfigSet(sid: sid, rid: 1 << 40, body: Uint8List(kAiMaxBodyBytes)),
      AiPrompt(
        sid: sid,
        rid: 1 << 40,
        text: 'a' * kAiMaxPromptBytes,
        blobs: List.filled(5, 1 << 40),
        files: List.filled(kAiMaxPromptFiles, 'a' * kAiMaxPathBytes),
      ),
      AiDiff(
        sid: sid,
        rid: 1 << 40,
        turn: 1 << 30,
        path: 'a' * kAiMaxPathBytes,
      ),
    ];
    for (final message in largest) {
      expect(
        encodeBatch([message]).length,
        lessThan(kMaxSealedBatchBytes),
        reason: message.type,
      );
    }
  });

  test('kAiProtocol is 2, and session.list.result carries it', () {
    expect(kAiProtocol, 2);
    const result = SessionListResult([], desktopSharing: true, ai: kAiProtocol);
    final decoded = decodeBatch(encodeBatch([result])).single;
    expect((decoded as SessionListResult).ai, 2);
  });

  group('compatibility with V2-2a peers (frozen decoder at d8ad686)', () {
    final added = samples.keys.where(
      (m) => m is! AiPrompt && m is! AiOpen && m is! AiResult,
    );

    test('a V2-2a phone or desktop skips every new kind and keeps its '
        'neighbours', () {
      final bytes = encodeBatch([
        const AckMessage(id: 1, seq: 2),
        ...added,
        const SessionReset(id: 1),
      ]);
      expect(v2.decodeBatch(bytes).map((m) => m.type), [
        'ack',
        'session.reset',
      ]);
    });

    test('a V2-2a phone reads a result with a body as the result it knows', () {
      final decoded =
          v2
                  .decodeBatch(
                    encodeBatch([
                      AiResult(rid: 3, ok: false, code: 'confirm', body: body),
                    ]),
                  )
                  .single
              as v2.AiResult;
      expect((decoded.rid, decoded.ok, decoded.code), (3, false, 'confirm'));
    });

    test('a V2-2a desktop reads a prompt with images and files as its text '
        'alone, and an open with resume as a new session — which is why a '
        'phone sends neither without the feature (B1)', () {
      final [prompt, open] = v2.decodeBatch(
        encodeBatch([
          const AiPrompt(
            sid: 'e.1',
            rid: 1,
            text: 'x',
            blobs: [1],
            files: ['a'],
          ),
          const AiOpen(rid: 2, agent: 'claude', folder: 'ws:a', resume: 's'),
        ]),
      );
      expect((prompt as v2.AiPrompt).text, 'x');
      expect((open as v2.AiOpen).folder, 'ws:a');
    });

    test('a V2-2a peer reads session.list.result with ai 2 as before', () {
      final decoded =
          v2
                  .decodeBatch(
                    encodeBatch([
                      const SessionListResult(
                        [],
                        desktopSharing: true,
                        ai: kAiProtocol,
                      ),
                    ]),
                  )
                  .single
              as v2.SessionListResult;
      expect((decoded.desktopSharing, decoded.ai), (true, 2));
    });

    test('a peer older than V2-2 (frozen at 5e04dc8) still skips every '
        'ai.* message, new or not', () {
      final bytes = encodeBatch([
        const AckMessage(id: 1, seq: 2),
        ...samples.keys,
        const SessionReset(id: 1),
      ]);
      expect(v1.decodeBatch(bytes).map((m) => m.type), [
        'ack',
        'session.reset',
      ]);
    });
  });
}
