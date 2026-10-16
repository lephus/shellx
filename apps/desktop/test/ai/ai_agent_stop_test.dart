import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';

bool alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// V2-1 final review, "fix now": stopping an agent (a tab closed, ⌘Q, a
/// restart, another folder) leaves nothing it started running — a dev server
/// holding a port, a test run. Real processes, through the host the app
/// builds, so what `buildAiHost` hands the agent's stop is pinned too
/// (`killTree: killProcessTree`).
void main() {
  late Directory tmp;
  final strangers = <int>[];
  setUp(() => tmp = Directory.systemTemp.createTempSync('ai_agent_stop'));
  tearDown(() {
    // A test that failed midway must not leave processes behind: these pids
    // are the ones the test itself started.
    for (final pid in strangers) {
      if (alive(pid)) Process.killPid(pid, ProcessSignal.sigkill);
    }
    strangers.clear();
    tmp.deleteSync(recursive: true);
  });

  Future<int> pidIn(File file) async {
    for (var i = 0; i < 200 && !file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    // The shell wrote the line as it started the child: a beat for it to be
    // complete.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final pid = int.parse(file.readAsStringSync().trim());
    strangers.add(pid);
    return pid;
  }

  Future<bool> goneSoon(int pid) async {
    for (var i = 0; i < 60; i++) {
      if (!alive(pid)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  AgentCommand shell(String script) => AgentCommand(
    executable: '/bin/sh',
    args: ['-c', script],
    environment: const {'PATH': '/usr/bin:/bin'},
  );

  test('an agent that exits when stdin closes, leaving a child it started '
      '(a dev server, a test run): stop() takes the child too', () async {
    final pidFile = File('${tmp.path}/child.pid');
    final host = buildAiHost(supportDir: tmp.path, version: 'test');
    final agent = await host.launch(
      shell('sleep 60 & echo \$! > "${pidFile.path}"; cat > /dev/null; exit 0'),
      cwd: tmp.path,
    );
    final child = await pidIn(pidFile);
    expect(alive(child), isTrue);
    await agent.stop();
    expect(await agent.exitCode, 0);
    expect(await goneSoon(child), isTrue, reason: 'the child survived stop()');
    for (var i = 0; i < 100 && host.running.read().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(host.running.read(), isEmpty);
  }, skip: Platform.isWindows);

  test('the app\'s host stops an agent with its tree: what an agent starts '
      'after stdin closed goes too (pins killTree: killProcessTree)', () async {
    final lateFile = File('${tmp.path}/late.pid');
    final host = buildAiHost(supportDir: tmp.path, version: 'test');
    // The agent starts a child only when stdin closes, and then stays: it has
    // to be killed after the grace, and the child was not there to be seen
    // beforehand — only a kill of the live tree takes it.
    final agent = await host.launch(
      shell(
        'cat > /dev/null; sleep 61 & echo \$! > "${lateFile.path}"; '
        'sleep 30',
      ),
      cwd: tmp.path,
    );
    await agent.stop();
    await agent.exitCode.timeout(const Duration(seconds: 10));
    final late = await pidIn(lateFile);
    expect(await goneSoon(late), isTrue, reason: 'the tree was not killed');
  }, skip: Platform.isWindows);

  test('a process that is not the agent\'s is left alone', () async {
    final pidFile = File('${tmp.path}/child.pid');
    final bystander = await Process.start('/bin/sleep', ['60']);
    strangers.add(bystander.pid);
    final host = buildAiHost(supportDir: tmp.path, version: 'test');
    final agent = await host.launch(
      shell('sleep 60 & echo \$! > "${pidFile.path}"; cat > /dev/null; exit 0'),
      cwd: tmp.path,
    );
    final child = await pidIn(pidFile);
    await agent.stop();
    expect(await goneSoon(child), isTrue);
    expect(alive(bystander.pid), isTrue);
  }, skip: Platform.isWindows);
}
