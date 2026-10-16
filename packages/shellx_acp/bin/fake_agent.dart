import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/testing.dart';

/// A scripted ACP agent process for tests:
/// `dart [--packages=…] bin/fake_agent.dart <scenario.json>`.
/// Logs what it receives to stderr (`RECV …`); exits 0 when stdin closes.
Future<void> main(List<String> args) async {
  final scenario = FakeScenario.fromJson(
    jsonDecode(File(args.single).readAsStringSync()) as Map<String, Object?>,
  );
  final agent = FakeAgent(
    scenario,
    input: stdin,
    output: stdout,
    stderr: stderr.writeln,
    onExit: (code) {
      stdout.flush().whenComplete(() => exit(code));
    },
  );
  await agent.connection.done;
  await stdout.done
      .timeout(const Duration(seconds: 2), onTimeout: () {})
      .catchError((Object _) {});
  exit(0);
}
