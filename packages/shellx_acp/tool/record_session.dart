import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';

/// Records one real ACP session as JSON lines (spec §12). Run by hand:
/// `dart tool/record_session.dart <node> <entry.js> <projectDir> <out.jsonl>`.
Future<void> main(List<String> args) async {
  final [node, entry, project, outPath] = args;
  final out = File(outPath).openWrite();
  // The output is RAW: scrub it and read all of it before committing it.
  // Bytes are split on newlines before decoding, so a character split
  // across two chunks stays whole.
  final pending = <String, List<int>>{'in': [], 'out': []};
  void log(String dir, List<int> bytes) {
    final buf = pending[dir]!..addAll(bytes);
    var start = 0;
    for (var nl = buf.indexOf(10); nl >= 0; nl = buf.indexOf(10, start)) {
      final line = utf8.decode(buf.sublist(start, nl), allowMalformed: true);
      start = nl + 1;
      if (line.trim().isEmpty) continue;
      try {
        out.writeln(jsonEncode({'dir': dir, 'msg': jsonDecode(line)}));
      } on FormatException {
        out.writeln(jsonEncode({'dir': dir, 'raw': line.length}));
      }
    }
    buf.removeRange(0, start);
  }

  // Inside means the canonical project folder itself or below it.
  final root = Uri.directory(Directory(project).absolute.path).normalizePath();
  bool inside(String path) {
    final file = Uri.file(path).normalizePath();
    return file.path.startsWith(root.path) && !file.pathSegments.contains('..');
  }

  Future<(Process, AcpClient)> start() async {
    for (final b in pending.values) {
      b.clear();
    }
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
    // edits inside the scratch project and a bare `ls`; reject the rest.
    client.onPermission = (r) async {
      final kind = r.toolCall.kind;
      final paths = [
        for (final l in r.toolCall.locations ?? const <ToolLocation>[]) l.path,
      ];
      final title = r.toolCall.title ?? '';
      final ok =
          ((kind == ToolKind.read || kind == ToolKind.edit) &&
              paths.isNotEmpty &&
              paths.every(inside)) ||
          (kind == ToolKind.execute && title.trim() == 'ls');
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
