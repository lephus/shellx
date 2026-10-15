import 'dart:convert';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 10, 15, 9);

AiSessionState _state() =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p');

void _tool(AiSessionState s, String id, Map<String, Object?> fields) =>
    s.applyUpdate(
      SessionUpdate.fromJson({
        'sessionUpdate': 'tool_call',
        'toolCallId': id,
        ...fields,
      }),
      _at,
    );

AiFullView _view(TimelineItem item) => AiFullView.fromJson(
  jsonDecode(aiFullItemJson(item)!) as Map<String, Object?>,
)!;

/// V2-2b B16, R14: an item in full, and its slices.
void main() {
  group('the full view', () {
    test('a tool call: its whole output (lines cut at 2 000), every diff '
        'whole, a new file, a file too big named only', () {
      final s = _state();
      final long = 'x' * 2500;
      final output = [
        for (var i = 0; i < 3000; i++) 'line $i',
        long,
      ].join('\n');
      _tool(s, 'c1', {
        'title': 'Run tests',
        'kind': 'execute',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': '\x1b[31m$output\x1b[0m'},
          },
          {
            'type': 'diff',
            'path': 'a.ts',
            'oldText': 'one\n',
            'newText': 'two\n',
          },
          {'type': 'diff', 'path': 'new.ts', 'oldText': null, 'newText': 'n\n'},
          {
            'type': 'diff',
            'path': 'huge.bin',
            'oldText': 'h',
            'newText': 'y' * (kAiFullDiffBytes + 1),
          },
        ],
        'rawInput': {'command': 'npm test'},
      });
      final view = _view(s.timeline.items.single);
      expect(view.kind, 'tool');
      expect(view.title, 'Run tests');
      final lines = view.output!.split('\n');
      expect(lines, hasLength(3001));
      expect(lines.first, 'line 0', reason: 'colours gone');
      expect(lines.last, '${'x' * kAiFullLineChars}…');
      expect(view.diffs.map((d) => (d.path, d.oldText, d.newText)), [
        ('a.ts', 'one\n', 'two\n'),
        ('new.ts', null, 'n\n'),
      ]);
      expect(view.bigDiffs, ['huge.bin']);
      expect(view.input, isNull, reason: 'only a call of kind other shows it');
    });

    test('the input of a call of kind other, indented', () {
      final s = _state();
      _tool(s, 'c1', {
        'title': 'mcp__db__query',
        'kind': 'other',
        'rawInput': {'sql': 'select 1', 'rows': 5},
      });
      expect(
        _view(s.timeline.items.single).input,
        '{\n  "sql": "select 1",\n  "rows": 5\n}',
      );
    });

    test(
      'a question\'s whole form; a text whole; nothing more for a turn end',
      () {
        final s = _state();
        final ask = s.addAsk(
          ElicitationRequest.fromJson({
            'mode': 'form',
            'message': 'Which?',
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'pick': {
                  'type': 'string',
                  'enum': ['a', 'b'],
                },
              },
            },
          }),
        )!;
        final form = _view(ask.item).request;
        expect(form, isA<ElicitationForm>());
        expect(form!.message, 'Which?');
        s.beginTurn([TextBlock('ữ' * 100000)], _at);
        final user = _view(s.timeline.items.whereType<UserItem>().single);
        expect((user.kind, user.text!.length), ('user', 100000));
        final end = s.endTurn(outcome: TurnOutcome.finished, at: _at)!;
        expect(aiFullItemJson(end), isNull);
      },
    );

    test('toString never shows what it holds', () {
      expect(const AiFullView(kind: 'agent', text: 'secret').toString(), '…');
    });
  });

  group('slices (R14)', () {
    void check(String text, {int maxBytes = kAiSliceBytes}) {
      final ends = aiSliceEnds(text, maxBytes: maxBytes);
      expect(ends.last, text.length);
      var start = 0;
      final joined = StringBuffer();
      for (final end in ends) {
        expect(end > start || text.isEmpty, isTrue, reason: 'no empty slice');
        final slice = text.substring(start, end);
        // Escaped for JSON, the slice is within the limit.
        expect(
          utf8.encode(jsonEncode(slice)).length - 2,
          lessThanOrEqualTo(maxBytes),
        );
        // Never between the two halves of a surrogate pair.
        if (end > 0 && end < text.length) {
          final before = text.codeUnitAt(end - 1);
          final after = text.codeUnitAt(end);
          expect(
            before >= 0xD800 &&
                before <= 0xDBFF &&
                after >= 0xDC00 &&
                after <= 0xDFFF,
            isFalse,
          );
        }
        joined.write(slice);
        start = end;
      }
      expect(joined.toString(), text);
    }

    test('plain, multi-byte and emoji text', () {
      check('a' * 100000);
      check('ữ' * 50000);
      check('😀' * 30000);
      check('');
    });

    test('Review Focus 3: quotes, backslashes and control characters, the '
        'worst escaping, still fit', () {
      check('"' * 60000);
      check('\\' * 60000);
      check('\u0001' * 60000);
      check(String.fromCharCodes([for (var i = 0; i < 70000; i++) i % 32]));
      check('\uD800' * 20000); // lone surrogates
    });

    test('a small limit cuts small, and never inside a pair', () {
      check('a😀b😀c' * 10, maxBytes: 5);
    });
  });
}
