import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show addTearDown;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_off_thread.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';

/// A folder that exists (the runtime checks it, D6) and that nothing
/// writes to: these runtimes never touch the disk.
String get testAiCwd => Directory.systemTemp.path;

/// AI runtimes over [FakeLauncher] (V2-1a): no process, no login shell,
/// no git (undo off unless [checkpoints]), every agent ready unless
/// [readiness] says otherwise, off-thread work done inline.
final class FakeAiRuntimes {
  FakeAiRuntimes(
    FakeScenario first, {
    List<FakeScenario> later = const [],
    this.checkpoints,
    this.readiness,
  }) : launcher = FakeLauncher(first, later);

  final FakeLauncher launcher;
  final Checkpoints? checkpoints;

  /// What every agent's check answers (null: ready); a test may change it
  /// (an install that worked).
  AgentReadiness? readiness;
  final made = <AiRuntime>[];
  final requests = <AiRuntimeRequest>[];

  static const ready = AgentReady(AgentCommand(executable: 'fake-agent'));

  AiRuntime make(AiRuntimeRequest r) {
    requests.add(r);
    _syncFolderCheck(r.cwd);
    final ckpt = checkpoints;
    final runtime = AiRuntime(
      state: AiSessionState(
        agentId: r.agent.id,
        agentName: r.agent.name,
        cwd: r.cwd,
      ),
      resolve: () async => readiness ?? ready,
      launch: launcher.call,
      clientVersion: 'test',
      checkpoints: ckpt == null ? null : () async => (ckpt, null),
      resumeSessionId: r.resumeSessionId,
      preferredConfig: r.preferredConfig,
    );
    made.add(runtime);
    return runtime;
  }

  /// The agent of launch [n] (0: the first).
  FakeAgent agent([int n = 0]) => launcher.channels[n].agent;

  List<Override> get overrides => [
    aiRuntimeFactoryProvider.overrideWithValue(make),
    aiOffThreadProvider.overrideWithValue(inlineOffThread),
    aiReadinessSourceProvider.overrideWithValue(
      (_) async => readiness ?? ready,
    ),
  ];
}

/// The landed `AiRuntime.start` checks its folder with
/// `Directory(cwd).exists()`: real async IO, which never completes under the
/// fake clock of a widget test. For the folders of these runtimes, that check
/// answers from `existsSync()` inside the test's own zone (what V2-1a's plan
/// did); every other call goes to the real `Directory`, and other folders
/// are not touched. Undone when the test ends.
void _syncFolderCheck(String folder) {
  var checks = _checks;
  if (checks == null) {
    checks = _checks = _SyncFolderChecks();
    IOOverrides.global = checks;
    addTearDown(() {
      IOOverrides.global = null;
      _checks = null;
    });
  }
  checks.folders.add(folder);
}

_SyncFolderChecks? _checks;

final class _SyncFolderChecks extends IOOverrides {
  final folders = <String>{};

  @override
  Directory createDirectory(String path) {
    final real = super.createDirectory(path);
    return folders.contains(path) ? _SyncExists(real) : real;
  }
}

/// A real [Directory] whose `exists()` answers in the caller's zone.
final class _SyncExists implements Directory {
  _SyncExists(this._real);

  final Directory _real;

  @override
  Future<bool> exists() async => _real.existsSync();

  @override
  bool existsSync() => _real.existsSync();

  @override
  String get path => _real.path;

  @override
  Uri get uri => _real.uri;

  @override
  bool get isAbsolute => _real.isAbsolute;

  @override
  Directory get absolute => _real.absolute;

  @override
  Directory get parent => _real.parent;

  @override
  Future<Directory> create({bool recursive = false}) =>
      _real.create(recursive: recursive);

  @override
  void createSync({bool recursive = false}) =>
      _real.createSync(recursive: recursive);

  @override
  Future<Directory> createTemp([String? prefix]) => _real.createTemp(prefix);

  @override
  Directory createTempSync([String? prefix]) => _real.createTempSync(prefix);

  @override
  Future<String> resolveSymbolicLinks() => _real.resolveSymbolicLinks();

  @override
  String resolveSymbolicLinksSync() => _real.resolveSymbolicLinksSync();

  @override
  Future<Directory> rename(String newPath) => _real.rename(newPath);

  @override
  Directory renameSync(String newPath) => _real.renameSync(newPath);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _real.delete(recursive: recursive);

  @override
  void deleteSync({bool recursive = false}) =>
      _real.deleteSync(recursive: recursive);

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => _real.list(recursive: recursive, followLinks: followLinks);

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => _real.listSync(recursive: recursive, followLinks: followLinks);

  @override
  Future<FileStat> stat() => _real.stat();

  @override
  FileStat statSync() => _real.statSync();

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => _real.watch(events: events, recursive: recursive);

  @override
  String toString() => _real.toString();
}
