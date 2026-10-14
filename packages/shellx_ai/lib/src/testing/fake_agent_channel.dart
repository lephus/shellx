import 'dart:async';

import 'package:shellx_acp/testing.dart';

import '../host/agent_catalog.dart';
import '../host/agent_process.dart';

/// An in-process [AgentChannel] around a [FakeAgent]: no process, same
/// lifecycle. Closing stdin makes it exit 0; [kill] exits -9.
final class FakeAgentChannel implements AgentChannel {
  FakeAgentChannel(FakeScenario scenario, {String? cwd}) {
    agent = FakeAgent(
      scenario,
      input: _toAgent.stream,
      output: _toClient.sink,
      cwd: cwd,
      stderr: _stderr.writeln,
      onExit: _exit,
    );
    agent.connection.done.then((_) => _exit(0));
  }

  late final FakeAgent agent;
  final _toAgent = StreamController<List<int>>();
  final _toClient = StreamController<List<int>>();
  final _exitCode = Completer<int>();
  final _stderr = StringBuffer();
  var stopCalls = 0;
  var killCalls = 0;

  bool get exited => _exitCode.isCompleted;

  void _exit(int code) {
    if (_exitCode.isCompleted) return;
    _exitCode.complete(code);
    unawaited(_toClient.close());
  }

  @override
  Stream<List<int>> get stdout => _toClient.stream;

  @override
  StreamSink<List<int>> get stdin => _toAgent.sink;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  String get stderrTail => _stderr.toString();

  @override
  Future<void> stop() async {
    stopCalls++;
    unawaited(_toAgent.close());
    await exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _exit(-9);
        return -9;
      },
    );
  }

  @override
  Future<void> kill() async {
    killCalls++;
    _exit(-9);
  }
}

/// An [AgentLauncher] that hands out [FakeAgentChannel]s and remembers
/// them. Launch 0 uses [first], launch n uses `later[n - 1]` (the last one
/// repeats), so a restarted agent can behave differently.
final class FakeLauncher {
  FakeLauncher(this.first, [this.later = const []]);

  final FakeScenario first;
  final List<FakeScenario> later;
  final channels = <FakeAgentChannel>[];
  final commands = <AgentCommand>[];

  Future<AgentChannel> call(AgentCommand command, {required String cwd}) async {
    commands.add(command);
    final n = channels.length;
    final scenario = n == 0 || later.isEmpty
        ? first
        : later[(n - 1).clamp(0, later.length - 1)];
    final channel = FakeAgentChannel(scenario, cwd: cwd);
    channels.add(channel);
    return channel;
  }
}
