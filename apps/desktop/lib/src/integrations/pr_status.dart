import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/config_controller.dart' show shellxConfigProvider;
import '../terminal/local_sessions_provider.dart' show homeDirectoryProvider;
import 'gh_locator.dart';
import 'pr_status_parse.dart';

/// A12 D16 limits.
const Duration kPrTimeout = Duration(seconds: 8);
const Duration kPrRefresh = Duration(seconds: 120);
const Duration kPrNone = Duration(minutes: 10);
const int kPrPerMinute = 6;
const List<Duration> kPrBackoff = [
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 20),
  Duration(minutes: 30),
];

/// A tab that has not been looked at for this long is not refreshed by the
/// timer (it is when it is looked at again).
const Duration kPrInterest = Duration(minutes: 15);
const int _maxEntries = 64;
const int _maxOutput = 256 * 1024;

/// The one argument vector ShellX ever gives `gh`: nothing the user typed is
/// in it (the branch and folder are only keys of the cache).
const List<String> kGhPrViewArgs = ['pr', 'view', '--json', kPrFields];

/// What the service adds to `gh`'s environment: three switches that keep it
/// quiet. No token, no host: `gh` finds its own login the way it does in a
/// terminal, and ShellX never reads it.
Map<String, String> ghEnvironment() => const {
  'GH_PROMPT_DISABLED': '1',
  'GH_NO_UPDATE_NOTIFIER': '1',
  'NO_COLOR': '1',
};

/// How `gh` ended. [toString] hides the output (it is the user's).
@immutable
final class GhResult {
  const GhResult(this.exitCode, this.stdout, this.stderr) : timedOut = false;
  const GhResult.timedOut()
    : exitCode = -1,
      stdout = '',
      stderr = '',
      timedOut = true;
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  @override
  String toString() => '…';
}

abstract interface class GhRunner {
  Future<GhResult> run(
    String exe,
    List<String> args, {
    required String cwd,
    required Duration timeout,
  });
}

/// Runs the real `gh`: no shell, no stdin, the output capped, the process
/// killed when it takes too long.
final class ProcessGhRunner implements GhRunner {
  const ProcessGhRunner();

  @override
  Future<GhResult> run(
    String exe,
    List<String> args, {
    required String cwd,
    required Duration timeout,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        exe,
        args,
        workingDirectory: cwd,
        includeParentEnvironment: true,
        environment: ghEnvironment(),
        runInShell: false,
      );
    } on ProcessException {
      return const GhResult(-1, '', '');
    } on FileSystemException {
      return const GhResult(-1, '', ''); // the folder is gone
    }
    unawaited(process.stdin.close().catchError((Object _) {}));
    final out = _capture(process.stdout);
    final err = _capture(process.stderr);
    try {
      final code = await process.exitCode.timeout(timeout);
      return GhResult(code, await out, await err);
    } on TimeoutException {
      if (Platform.isWindows) {
        // gh starts git: take the tree down, not just the parent.
        unawaited(
          Process.run('taskkill', [
            '/F',
            '/T',
            '/PID',
            '${process.pid}',
          ]).then<void>((_) {}).catchError((Object _) {}),
        );
      }
      process.kill(ProcessSignal.sigkill);
      return const GhResult.timedOut();
    }
  }

  static Future<String> _capture(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length < _maxOutput) {
        bytes.addAll(chunk.take(_maxOutput - bytes.length));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// The folder and branch to ask about, or null: only a local pane (an SSH
/// pane's folder is on another computer) that has both.
(String, String)? prTargetOf({
  required bool remote,
  required String? cwd,
  required String? branch,
}) {
  if (remote || cwd == null || cwd.isEmpty) return null;
  if (branch == null || branch.isEmpty) return null;
  return (cwd, branch);
}

/// The git root above [dir] (a `.git` folder or file), or null. Only `.git`
/// is looked for at each level.
Future<String?> findGitRoot(String dir) async {
  var current = dir;
  for (var i = 0; i < 64; i++) {
    try {
      final sep = Platform.isWindows ? r'\' : '/';
      final dotGit = current.endsWith(sep)
          ? '$current.git'
          : '$current$sep.git';
      if (await FileSystemEntity.type(dotGit) !=
          FileSystemEntityType.notFound) {
        return current;
      }
    } on Object {
      return null;
    }
    final parent = Directory(current).parent.path;
    if (parent == current) return null;
    current = parent;
  }
  return null;
}

final class _Entry {
  PrInfo? info;
  DateTime? nextAt;
  int failures = 0;
  DateTime wantedAt;
  bool queued = false;
  _Entry(this.wantedAt);
}

typedef _Key = (String root, String branch);

/// A12 D16: pull request status through the GitHub CLI. One lookup at a
/// time, at most [kPrPerMinute] a minute for the whole app, a lookup only
/// for something someone [want]s, results kept ([kPrRefresh], [kPrNone]),
/// failures backed off ([kPrBackoff]). Nothing here logs.
class PrStatusService {
  PrStatusService({
    required GhRunner runner,
    required Future<String?> Function() findGh,
    required Future<String?> Function(String dir) findRoot,
    DateTime Function()? now,
    void Function()? onChange,
  }) : _runner = runner,
       _findGh = findGh,
       _findRoot = findRoot,
       _now = now ?? DateTime.now,
       _onChange = onChange;

  final GhRunner _runner;
  final Future<String?> Function() _findGh;
  final Future<String?> Function(String dir) _findRoot;
  final DateTime Function() _now;
  final void Function()? _onChange;

  final _entries = <_Key, _Entry>{};
  final _queue = <_Key>[];
  final _calls = <DateTime>[];
  final _roots = <String, ({String? root, DateTime at})>{};
  final _rootLookups = <String, Set<String>>{};
  bool _running = false;
  bool _disposed = false;
  Timer? _pumpTimer, _refreshTimer;

  /// The last search for `gh` found nothing (the Settings row says so).
  bool ghMissing = false;

  String? _rootOf(String dir) {
    final cached = _roots[dir];
    if (cached == null) return null;
    final age = _now().difference(cached.at);
    if (age > (cached.root == null ? const Duration(minutes: 1) : kPrNone)) {
      _roots.remove(dir);
      return null;
    }
    return cached.root;
  }

  /// What is known for [branch] of the repository around [dir]; never
  /// starts a lookup.
  PrInfo? peek(String dir, String branch) {
    final root = _rootOf(dir);
    return root == null ? null : _entries[(root, branch)]?.info;
  }

  /// Someone is looking at [branch] in [dir]: look it up when it is due.
  void want(String dir, String branch) {
    if (_disposed || dir.isEmpty || branch.isEmpty) return;
    final root = _rootOf(dir);
    if (root != null) {
      _wantRoot(root, branch);
      return;
    }
    if (_roots.containsKey(dir)) return; // not in a repository (for now)
    final waiting = _rootLookups[dir];
    if (waiting != null) {
      waiting.add(branch); // the same lookup answers every branch asked
      return;
    }
    _rootLookups[dir] = {branch};
    unawaited(() async {
      String? found;
      try {
        found = await _findRoot(dir);
      } on Object {
        found = null;
      }
      final branches = _rootLookups.remove(dir) ?? const <String>{};
      if (_disposed) return;
      _roots[dir] = (root: found, at: _now());
      while (_roots.length > _maxEntries) {
        _roots.remove(_roots.keys.first);
      }
      if (found != null) {
        for (final b in branches) {
          _wantRoot(found, b);
        }
      }
    }());
  }

  void _wantRoot(String root, String branch) {
    final key = (root, branch);
    final now = _now();
    final entry = _entries.putIfAbsent(key, () => _Entry(now));
    entry.wantedAt = now;
    _prune();
    if (entry.queued) return;
    final due = entry.nextAt;
    if (due != null && now.isBefore(due)) {
      _scheduleRefresh();
      return;
    }
    entry.queued = true;
    _queue.add(key);
    _pump();
  }

  void _prune() {
    while (_entries.length > _maxEntries) {
      final oldest = _entries.entries
          .where((e) => !e.value.queued)
          .fold<MapEntry<_Key, _Entry>?>(
            null,
            (a, b) => a == null || b.value.wantedAt.isBefore(a.value.wantedAt)
                ? b
                : a,
          );
      if (oldest == null) return;
      _entries.remove(oldest.key);
    }
  }

  void _pump() {
    if (_disposed || _running || _queue.isEmpty) return;
    final now = _now();
    _calls.removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
    if (_calls.length >= kPrPerMinute) {
      if (_pumpTimer == null) {
        final wait = _calls.first
            .add(const Duration(minutes: 1))
            .difference(now);
        _pumpTimer = Timer(wait, () {
          _pumpTimer = null;
          _pump();
        });
      }
      return;
    }
    final key = _queue.removeAt(0);
    _running = true;
    unawaited(_lookup(key));
  }

  Future<void> _lookup(_Key key) async {
    final entry = _entries[key];
    var changed = false;
    try {
      final gh = await _findGh();
      if (_disposed) return;
      ghMissing = gh == null;
      if (gh == null) {
        // Off, quietly; looked for again when the locator's answer expires.
        entry?.nextAt = _now().add(kGhLocatorTtl);
        return;
      }
      _calls.add(_now());
      GhResult result;
      try {
        result = await _runner.run(
          gh,
          kGhPrViewArgs,
          cwd: key.$1,
          timeout: kPrTimeout,
        );
      } on Object {
        result = const GhResult.timedOut();
      }
      if (_disposed || entry == null) return;
      final now = _now();
      final before = entry.info;
      PrInfo? parsed;
      if (!result.timedOut && result.exitCode == 0) {
        parsed = parsePrJson(result.stdout);
      }
      if (parsed != null) {
        entry
          ..info = parsed
          ..failures = 0
          ..nextAt = now.add(kPrRefresh);
      } else if (!result.timedOut &&
          result.exitCode != 0 &&
          result.stderr.toLowerCase().contains('no pull requests found')) {
        entry
          ..info = null
          ..failures = 0
          ..nextAt = now.add(kPrNone);
      } else {
        entry
          ..info = null
          ..failures += 1
          ..nextAt = now.add(
            kPrBackoff[(entry.failures - 1).clamp(0, kPrBackoff.length - 1)],
          );
      }
      changed = before != entry.info;
    } finally {
      entry?.queued = false;
      _running = false;
      if (!_disposed) {
        if (changed) _onChange?.call();
        _scheduleRefresh();
        _pump();
      }
    }
  }

  /// One timer, for the soonest due entry somebody still looks at.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_disposed) return;
    final now = _now();
    DateTime? soonest;
    for (final e in _entries.values) {
      final due = e.nextAt;
      if (due == null || e.queued) continue;
      if (now.difference(e.wantedAt) > kPrInterest) continue;
      if (soonest == null || due.isBefore(soonest)) soonest = due;
    }
    if (soonest == null) return;
    final wait = soonest.difference(now);
    _refreshTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _refreshTimer = null;
      final at = _now();
      for (final MapEntry(:key, :value) in _entries.entries) {
        final due = value.nextAt;
        if (due == null || value.queued || at.isBefore(due)) continue;
        if (at.difference(value.wantedAt) > kPrInterest) continue;
        value.queued = true;
        _queue.add(key);
      }
      _pump();
      _scheduleRefresh();
    });
  }

  void dispose() {
    _disposed = true;
    _pumpTimer?.cancel();
    _refreshTimer?.cancel();
    _pumpTimer = _refreshTimer = null;
    _queue.clear();
  }
}

// ---- providers -------------------------------------------------------

final ghRunnerProvider = Provider<GhRunner>((_) => const ProcessGhRunner());

/// Where `gh` is (searched at most every 5 minutes).
final ghFinderProvider = Provider<Future<String?> Function()>((ref) {
  final env = Platform.environment;
  return GhLocator(
    path: env['PATH'] ?? '',
    home: ref.read(homeDirectoryProvider),
    windows: Platform.isWindows,
    programFiles: env['ProgramFiles'],
  ).find;
});

final repoRootFinderProvider = Provider<Future<String?> Function(String)>(
  (_) => findGitRoot,
);

/// Bumped when a lookup changed what a row shows.
final prRevisionProvider = NotifierProvider<PrRevision, int>(PrRevision.new);

class PrRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final prStatusServiceProvider = Provider<PrStatusService>((ref) {
  final service = PrStatusService(
    runner: ref.watch(ghRunnerProvider),
    findGh: ref.watch(ghFinderProvider),
    findRoot: ref.watch(repoRootFinderProvider),
    onChange: () => ref.read(prRevisionProvider.notifier).bump(),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Whether `gh` can be found (the Settings row's note).
final ghFoundProvider = FutureProvider.autoDispose<bool>(
  (ref) async => await ref.read(ghFinderProvider)() != null,
);

/// What a row asks for.
typedef PrQuery = ({String? cwd, String? branch, bool remote, bool visible});

/// The pull request for a tab's row, or null: the switch is off, the pane
/// is remote, there is no branch, nothing is known yet. A visible row also
/// asks for a lookup (the service decides if and when).
final prChipProvider = Provider.autoDispose.family<PrInfo?, PrQuery>((ref, q) {
  final on = ref.watch(shellxConfigProvider.select((s) => s.config.prStatus));
  if (!on) return null;
  final target = prTargetOf(remote: q.remote, cwd: q.cwd, branch: q.branch);
  if (target == null) return null;
  ref.watch(prRevisionProvider);
  final service = ref.watch(prStatusServiceProvider);
  if (q.visible) {
    // Not while building: the service may start work.
    scheduleMicrotask(() => service.want(target.$1, target.$2));
  }
  return service.peek(target.$1, target.$2);
});
