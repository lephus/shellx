import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:test/test.dart';

/// A real Claude adapter 0.90.0 session (spec §12), recorded with
/// `tool/record_session.dart` and scrubbed (paths, personal plugin names).
void main() {
  final file = File('test/fixtures/sessions/claude-agent-acp-0.90.0.jsonl');
  final lines = file.existsSync()
      ? [
          for (final l in file.readAsLinesSync())
            if (l.trim().isNotEmpty) jsonDecode(l) as JsonMap,
        ]
      : <JsonMap>[];
  final skip = lines.isEmpty
      ? 'no recorded session (ledger: pending manual)'
      : false;

  Iterable<JsonMap> incoming(String method) => [
    for (final l in lines)
      if (l['dir'] == 'in' && (l['msg']! as JsonMap)['method'] == method)
        (l['msg']! as JsonMap)['params']! as JsonMap,
  ];

  test('every update of the real Claude session parses', () {
    final kinds = <String>{};
    for (final p in incoming('session/update')) {
      final update = p['update']! as JsonMap;
      kinds.add(update['sessionUpdate']! as String);
      expect(
        SessionUpdate.fromJson(update),
        isNot(isA<UnknownUpdate>()),
        reason: '${update['sessionUpdate']}',
      );
    }
    expect(
      kinds,
      containsAll([
        'agent_message_chunk',
        'tool_call',
        'tool_call_update',
        'usage_update',
      ]),
    );
  }, skip: skip);

  test('the tool kinds of the real session map to cards', () {
    final toolKinds = <ToolKind?>{
      for (final p in incoming('session/update'))
        if (SessionUpdate.fromJson(p['update']! as JsonMap)
            case ToolCallStarted(:final fields))
          fields.kind,
    };
    expect(
      toolKinds,
      containsAll([ToolKind.read, ToolKind.edit, ToolKind.execute]),
    );
  }, skip: skip);

  test('the permission request carries the Claude options and the diff', () {
    final r = PermissionRequest.fromJson(
      incoming('session/request_permission').single,
    );
    expect(r.options.map((o) => o.kind), [
      PermissionKind.allowOnce,
      PermissionKind.allowAlways,
      PermissionKind.rejectOnce,
    ]);
    expect(r.toolCall.kind, ToolKind.edit);
    expect(
      r.toolCall.content!.single,
      isA<ToolDiff>().having((d) => d.newText, 'newText', 'hello ShellX'),
    );
  }, skip: skip);

  test(
    'initialize and the session results parse with terminal logins and config options',
    () {
      final results = [
        for (final l in lines)
          if (l['dir'] == 'in' && (l['msg']! as JsonMap).containsKey('result'))
            (l['msg']! as JsonMap)['result'],
      ];
      final init = InitializeResult.fromJson(results.first! as JsonMap);
      expect(init.protocolVersion, 1);
      expect(init.capabilities.loadSession, isTrue);
      expect(init.capabilities.listSessions, isTrue);
      expect(init.authMethods.map((m) => m.id), [
        'claude-ai-login',
        'console-login',
      ]);
      expect(init.authMethods.every((m) => m is AuthMethodTerminal), isTrue);
      final session = NewSessionResult.fromJson(results[1]! as JsonMap);
      expect(
        session.configOptions!.map((o) => o.id),
        containsAll(['mode', 'model', 'effort']),
      );
      expect(
        session.modes!.available.map((m) => m.id),
        contains('bypassPermissions'),
      );
    },
    skip: skip,
  );
}
