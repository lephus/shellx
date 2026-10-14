import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';

/// Records one real ACP session as JSON lines (spec §12). Run by hand:
/// `dart tool/record_session.dart <node> <entry.js> <projectDir> <out.jsonl>`.
Future<void> main(List<String> args) async {
  final [node, entry, project, outPath] = args;
  final out = File(outPath).openWrite();
  final pending = <String, StringBuffer>{
    'in': StringBuffer(),
    'out': StringBuffer(),
  };
  void log(String dir, List<int> bytes) {
    final buf = pending[dir]!..write(utf8.decode(bytes, allowMalformed: true));
    final text = buf.toString();
    final cut = text.lastIndexOf('\n');
    if (cut < 0) return;
    buf
      ..clear()
      ..write(text.substring(cut + 1));
    for (final line in const LineSplitter().convert(text.substring(0, cut))) {
      if (line.trim().isEmpty) continue;
      try {
        out.writeln(jsonEncode({'dir': dir, 'msg': jsonDecode(line)}));
      } on FormatException {
        out.writeln(jsonEncode({'dir': dir, 'raw': line.length}));
      }
    }
  }

  Future<(Process, AcpClient)> start() async {
    final p = await Process.start(node, [entry], workingDirectory: project);
    p.stderr.drain<void>();
    final toAgent = StreamController<List<int>>();
    toAgent.stream.listen((b) {
      log('out', b);
      p.stdin.add(b);
    }, onDone: p.stdin.close);
    final fromAgent = p.stdout.map((b) {
      log('in', b);
      return b;
    });
    final client = AcpClient(
      JsonRpcConnection(input: fromAgent, output: toAgent.sink),
    );
    // The recording's own policy (never ShellX's): allow once only reads and
    // edits inside the scratch project and an `ls`; reject anything else.
    client.onPermission = (r) async {
      final kind = r.toolCall.kind;
      final paths = [
        for (final l in r.toolCall.locations ?? const <ToolLocation>[]) l.path,
      ];
      final inside =
          paths.isNotEmpty && paths.every((x) => x.startsWith(project));
      final title = r.toolCall.title ?? '';
      final ok =
          ((kind == ToolKind.read || kind == ToolKind.edit) && inside) ||
          (kind == ToolKind.execute &&
              RegExp(r'^ls( |$)').hasMatch(title.trim()));
      stdout.writeln('permission: ${kind?.wire} ok=$ok');
      final want = ok ? PermissionKind.allowOnce : PermissionKind.rejectOnce;
      final option = r.options.where((o) => o.kind == want).firstOrNull;
      return option == null
          ? const PermissionCancelled()
          : PermissionSelected(option.optionId);
    };
    client.onElicitation = (r) async => const ElicitDecline();
    return (p, client);
  }

  Future<void> stop(Process p, AcpClient client) async {
    await client.close();
    await p.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -9;
      },
    );
  }

  var (p, client) = await start();
  final init = await client.initialize(clientVersion: '0.0.0-record');
  stdout.writeln(
    'agent: ${init.agentInfo?.name} protocol ${init.protocolVersion} load=${init.capabilities.loadSession}',
  );
  final String sid;
  try {
    sid = (await client.newSession(cwd: project)).sessionId;
  } on JsonRpcError catch (e) {
    stdout.writeln('session/new failed: ${e.code}');
    await stop(p, client);
    await out.close();
    exitCode = 2;
    return;
  }
  final reason = await client.prompt(sid, const [
    TextBlock(
      'Read hello.txt, then change the word world to ShellX in it, then run the command ls.',
    ),
  ]);
  stdout.writeln('stopReason: ${reason.wire}');
  await client.listSessions(cwd: project);
  await stop(p, client);

  (p, client) = await start();
  await client.initialize(clientVersion: '0.0.0-record');
  await client.loadSession(sessionId: sid, cwd: project);
  await stop(p, client);
  await out.close();
}
