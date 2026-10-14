import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:test/test.dart';

const hi = [TextBlock('hi')];

/// What every rig resolves to; the in-process launcher ignores it.
const fakeCommand = AgentCommand(executable: 'fake-agent', args: ['--acp']);

/// An [AiRuntime] on in-process fake agents, in a temp project. The brief's
/// own `Rig` (in `ai_runtime_test.dart`) stays as written; this one adds the
/// knobs the contract tests need (a custom launcher, the initialize timeout).
final class RuntimeRig {
  RuntimeRig({
    FakeScenario first = const FakeScenario(),
    List<FakeScenario> later = const [],
    AgentLauncher? launch,
    Future<AgentReadiness> Function()? resolve,
    Future<(Checkpoints?, UndoOff?)> Function()? checkpoints,
    bool realCheckpoints = false,
    String? resume,
    Map<String, Object> preferred = const {},
    Duration initializeTimeout = const Duration(seconds: 30),
    Duration cancelGrace = const Duration(seconds: 10),
  }) : tmp = Directory.systemTemp.createTempSync('runtime_contract') {
    Directory(project).createSync();
    launcher = FakeLauncher(first, later);
    final stores = CheckpointStores(
      root: p.join(tmp.path, 'support', 'ai', 'checkpoints'),
    );
    runtime = AiRuntime(
      state: AiSessionState(agentId: 'fake', agentName: 'Fake', cwd: project),
      resolve: resolve ?? () async => const AgentReady(fakeCommand),
      launch: launch ?? launcher.call,
      clientVersion: '2.0.0',
      checkpoints:
          checkpoints ??
          (realCheckpoints
              ? () async => stores.forProject(
                  project,
                  LoginEnv(
                    Platform.environment,
                    source: LoginEnvSource.process,
                  ),
                )
              : null),
      resumeSessionId: resume,
      preferredConfig: preferred,
      initializeTimeout: initializeTimeout,
      cancelGrace: cancelGrace,
      sessionKey: 'k1',
    )..onStatus = statuses.add;
  }

  final Directory tmp;
  late final FakeLauncher launcher;
  late final AiRuntime runtime;
  final statuses = <AiStatus>[];

  String get project => p.join(tmp.path, 'project');
  AiSessionState get state => runtime.state;
  FakeAgent agent([int i = -1]) =>
      (i < 0 ? launcher.channels.last : launcher.channels[i]).agent;

  /// The cards of the conversation, in order.
  List<NoticeItem> get cards =>
      state.timeline.items.whereType<NoticeItem>().toList();

  List<AiNotice> get notices => [for (final c in cards) c.notice];

  List<TurnEndItem> get turnEnds =>
      state.timeline.items.whereType<TurnEndItem>().toList();

  Future<void> until(bool Function() test, {int tries = 400}) async {
    for (var i = 0; i < tries && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(test(), isTrue, reason: 'condition not reached');
  }

  Future<void> dispose() async {
    await runtime.dispose();
    await deleteTree(tmp);
  }
}

/// Deletes [dir], trying again for a moment: a git or an agent that was just
/// stopped may still be closing a file under it.
Future<void> deleteTree(Directory dir) async {
  for (var attempt = 1; attempt <= 20 && dir.existsSync(); attempt++) {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      if (attempt == 20) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// Asks the runtime for permission the way an agent does, without waiting for
/// the answer inside a turn script: the future completes with the response.
Future<Object?> askPermission(FakeAgent agent, String id, String title) =>
    agent.connection.request('session/request_permission', {
      'sessionId': 'sess-1',
      'toolCall': {'toolCallId': id, 'title': title, 'kind': 'edit'},
      'options': FakeSteps.claudeOptions,
    });

/// Asks the runtime a question the way an agent does (`elicitation/create`);
/// the future completes with the response.
Future<Object?> askQuestion(FakeAgent agent, Map<String, Object?> request) =>
    agent.connection.request('elicitation/create', {
      'sessionId': 'sess-1',
      ...request,
    });

/// Counts the notifications at which a view could see a turn that is over
/// while a permission or a question still waits for an answer.
final class SettleWatch {
  SettleWatch(this.state) {
    state.addListener(_check);
  }

  final AiSessionState state;
  var checks = 0;
  var violations = 0;

  void _check() {
    checks++;
    if (state.turn == null && state.needsInput) violations++;
  }
}

/// An agent process that never says a word: it stays up until it is stopped
/// or killed. Its pipe closes [eofDelay] after the exit is reported, as the
/// pipes of a real process do (the exit and the end of stdout are separate
/// events).
final class SilentChannel implements AgentChannel {
  SilentChannel({this.eofDelay = Duration.zero}) {
    _stdin.stream.listen((bytes) => written += bytes.length);
  }

  final Duration eofDelay;
  final _stdout = StreamController<List<int>>();
  final _stdin = StreamController<List<int>>();
  final _exit = Completer<int>();

  /// Bytes the runtime wrote to the agent (its `initialize`).
  var written = 0;
  var stopCalls = 0;
  var killCalls = 0;

  bool get exited => _exit.isCompleted;

  void _end(int code) {
    if (_exit.isCompleted) return;
    _exit.complete(code);
    Timer(eofDelay, () => unawaited(_stdout.close()));
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  String get stderrTail => '';

  @override
  Future<void> stop() async {
    stopCalls++;
    _end(0);
  }

  @override
  Future<void> kill() async {
    killCalls++;
    _end(-9);
  }
}

/// An agent that ignores its stdin closing, as one that spawned a child can:
/// only a kill ends it.
final class StubbornChannel implements AgentChannel {
  StubbornChannel(this.inner);

  final FakeAgentChannel inner;

  @override
  Stream<List<int>> get stdout => inner.stdout;

  @override
  StreamSink<List<int>> get stdin => _KeepOpen(inner.stdin);

  @override
  Future<int> get exitCode => inner.exitCode;

  @override
  String get stderrTail => inner.stderrTail;

  @override
  Future<void> stop() => inner.stop();

  @override
  Future<void> kill() => inner.kill();
}

final class _KeepOpen implements StreamSink<List<int>> {
  _KeepOpen(this._inner);

  final StreamSink<List<int>> _inner;

  @override
  void add(List<int> data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);

  @override
  Future<void> close() => Future.value();

  @override
  Future<void> get done => _inner.done;
}

/// An agent that never says anything with [text] in it (one message per
/// chunk, as the in-process fake writes them).
final class SilentAbout implements AgentChannel {
  SilentAbout(this.inner, this.text);

  final FakeAgentChannel inner;
  final String text;

  @override
  Stream<List<int>> get stdout => inner.stdout.where(
    (chunk) => !utf8.decode(chunk, allowMalformed: true).contains(text),
  );

  @override
  StreamSink<List<int>> get stdin => inner.stdin;

  @override
  Future<int> get exitCode => inner.exitCode;

  @override
  String get stderrTail => inner.stderrTail;

  @override
  Future<void> stop() => inner.stop();

  @override
  Future<void> kill() => inner.kill();
}

/// Checkpoints without git. Every call is recorded in [calls]; each kind of
/// call can be made to throw.
final class RecordingCheckpoints implements Checkpoints {
  /// Refs whose snapshot throws.
  bool Function(String ref)? failSnapshot;

  /// Holds [currentTree] (the wrap-up of a turn) until it completes.
  Future<void>? treeGate;
  var failTree = false;
  var failQueries = false;
  var failRestore = false;
  final calls = <String>[];
  var _trees = 0;

  @override
  UndoOff? get off => null;

  @override
  Future<Checkpoint?> snapshot(String ref) async {
    calls.add('snapshot:$ref');
    if (failSnapshot?.call(ref) ?? false) throw StateError('snapshot');
    return Checkpoint(commit: 'c-$ref', tree: 't-$ref');
  }

  @override
  Future<String?> currentTree() async {
    calls.add('tree');
    final gate = treeGate;
    if (gate != null) await gate;
    if (failTree) throw StateError('tree');
    return 'after-${++_trees}';
  }

  @override
  Future<List<FileChange>> changes(String fromTree, [String? toTree]) async {
    calls.add('changes:$fromTree..${toTree ?? 'now'}');
    if (failQueries) throw StateError('changes');
    return const [FileChange(path: 'a.txt', kind: ChangeKind.modified)];
  }

  @override
  Future<Set<String>> changedSince(String tree) async {
    calls.add('changedSince:$tree');
    if (failQueries) throw StateError('changedSince');
    return const {'a.txt'};
  }

  @override
  Future<List<int>?> fileAt(String treeish, String path) async {
    calls.add('fileAt:$treeish:$path');
    if (failQueries) throw StateError('fileAt');
    return const [1, 2, 3];
  }

  @override
  Future<void> restore(String treeish, Iterable<String> paths) async {
    calls.add('restore:$treeish:${paths.join(',')}');
    if (failRestore) throw const FileSystemException('restore');
  }
}
