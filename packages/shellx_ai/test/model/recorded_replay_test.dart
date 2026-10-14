import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

void main() {
  final file = File(
    '../shellx_acp/test/fixtures/sessions/claude-agent-acp-0.90.0.jsonl',
  );
  final lines = file.existsSync()
      ? [for (final l in file.readAsLinesSync()) jsonDecode(l) as JsonMap]
      : <JsonMap>[];
  final skip = lines.isEmpty ? 'no recorded session (ledger)' : false;

  // The recording holds two runs: the live turn, then a restart with session/load.
  final secondInit = lines.indexWhere(
    (l) =>
        l['dir'] == 'out' && (l['msg']! as JsonMap)['method'] == 'initialize',
    1,
  );
  Iterable<SessionUpdate> updates(Iterable<JsonMap> part) sync* {
    for (final l in part) {
      final msg = l['msg']! as JsonMap;
      if (l['dir'] == 'in' && msg['method'] == 'session/update') {
        yield SessionUpdate.fromJson(
          (msg['params']! as JsonMap)['update']! as JsonMap,
        );
      }
    }
  }

  test(
    'the live turn draws text and finished read, edit and execute cards',
    () {
      final s = AiSessionState(
        agentId: 'claude',
        agentName: 'Claude',
        cwd: '/project',
      )..beginTurn(const [TextBlock('Read hello.txt…')], DateTime.utc(2026));
      for (final u in updates(
        lines.take(secondInit < 0 ? lines.length : secondInit),
      )) {
        s.applyUpdate(u, DateTime.utc(2026));
      }
      final tools = s.timeline.items.whereType<ToolItem>().toList();
      expect(
        tools.map((t) => t.fields.kind),
        containsAll([ToolKind.read, ToolKind.edit, ToolKind.execute]),
      );
      expect(tools.every((t) => t.end == ToolEnd.completed), isTrue);
      expect(
        s.timeline.items.whereType<AgentTextItem>().map((t) => t.text).join(),
        isNotEmpty,
      );
    },
    skip: skip,
  );

  test('session/load replays the prompt as the first turn', () {
    final s = AiSessionState(
      agentId: 'claude',
      agentName: 'Claude',
      cwd: '/project',
    );
    for (final u in updates(
      lines.skip(secondInit < 0 ? lines.length : secondInit),
    )) {
      s.applyUpdate(u, DateTime.utc(2026), history: true);
    }
    expect(
      s.timeline.items.whereType<UserItem>().first.text,
      contains('hello.txt'),
    );
  }, skip: skip);
}
