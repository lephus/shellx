import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart' show sha256Bytes;
import 'package:shellx_core/shellx_core.dart' show bytesToHex;

import '../config/config_controller.dart' show shellxConfigProvider;
import '../platform/process_tree.dart';
import '../platform/settings_store.dart';
import 'command_line.dart';

export 'command_line.dart';
import '../terminal/local_sessions_provider.dart' show homeDirectoryProvider;
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import '../terminal/terminal_tabs.dart';

/// A12 D17 limits.
const Duration kAgentCommandTimeout = Duration(seconds: 10);
const int kAgentCommandParallel = 4;
const int kAgentCommandQueue = 16;
const Duration kAgentCommandGap = Duration(seconds: 1);

const int _maxApproved = 20;

/// The only names of the app's environment the command inherits.
const List<String> kAgentCommandEnvNames = [
  'PATH',
  'HOME',
  'USER',
  'LOGNAME',
  'LANG',
  'TMPDIR',
  'SystemRoot',
];

/// The approval key of a command string: the hex SHA-256 of its UTF-8 bytes.
/// Any change to the string, a space included, is another key.
String commandHash(String command) =>
    bytesToHex(sha256Bytes(utf8.encode(command)));

final RegExp _hash = RegExp(r'^[0-9a-f]{64}$');

/// Whether the user allowed the command whose hash is [hash].
bool isCommandApproved(SettingsStore settings, String hash) =>
    _hash.hasMatch(hash) &&
    settings.getStrings(SettingKeys.agentCommandApproved).contains(hash);

/// Stores [hash] (never the string itself); the newest [_maxApproved] stay.
Future<void> approveCommand(SettingsStore settings, String hash) async {
  if (!_hash.hasMatch(hash)) return;
  final list = [
    for (final h in settings.getStrings(SettingKeys.agentCommandApproved))
      if (h != hash && _hash.hasMatch(h)) h,
    hash,
  ];
  await settings.setStrings(SettingKeys.agentCommandApproved, [
    for (final h in list.skip(
      list.length > _maxApproved ? list.length - _maxApproved : 0,
    ))
      h,
  ]);
}

/// One agent status event for the user's command. Its words come from the
/// agent and the pane: [toString] shows nothing.
@immutable
final class AgentCommandEvent {
  const AgentCommandEvent({
    required this.event,
    required this.agent,
    required this.pane,
    required this.tab,
    required this.status,
    this.message,
  });

  /// `running`, `needs_input`, `idle`, `done`, `end`.
  final String event;

  /// A name of the closed set (`claude`, `codex`, `gemini`, `opencode`).
  final String agent;
  final int pane;
  final int? tab;

  /// The state after the event; `none` when the agent ended.
  final String status;

  /// Already cleaned and clipped; null or empty: none.
  final String? message;

  /// stdin: `{"v":1,"event","agent","pane","tab","status","message?"}`.
  /// Not the workspace, a path or a branch.
  String jsonLine() => jsonEncode({
    'v': 1,
    'event': event,
    'agent': agent,
    'pane': pane,
    'tab': tab,
    'status': status,
    if (message != null && message!.isNotEmpty) 'message': message,
  });

  Map<String, String> env() => {
    'SHELLX_EVENT': event,
    'SHELLX_AGENT': agent,
    'SHELLX_PANE': '$pane',
    'SHELLX_TAB': '${tab ?? ''}',
    'SHELLX_STATUS': status,
  };

  @override
  String toString() => '…';
}

typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
      bool runInShell,
    });

/// A12 D17: runs the user's `agent-event-command` when an agent's state
/// changes. Only a command whose hash the user allowed; no shell; a
/// minimal environment (never the CLI token or socket); 10 s; 4 at a time;
/// a queue of 16 that drops the oldest; one a second per (pane, event); the
/// output thrown away. Nothing here logs. It lives in the window's process
/// only (the background service never creates one), so it runs once.
class AgentCommandRunner {
  AgentCommandRunner({
    required String Function() command,
    required bool Function(String hash) approved,
    required this.home,
    required Map<String, String> environment,
    required this.windows,
    required void Function(String command) onNotApproved,
    required void Function() onCouldNotRun,
    ProcessStarter? start,
    Future<void> Function(Process process)? killTree,
    DateTime Function()? now,
  }) : _command = command,
       _approved = approved,
       _environment = environment,
       _onNotApproved = onNotApproved,
       _onCouldNotRun = onCouldNotRun,
       _start = start ?? Process.start,
       _killTree = killTree ?? killProcessTree,
       _now = now ?? DateTime.now;

  final String Function() _command;
  final bool Function(String hash) _approved;
  final String home;
  final Map<String, String> _environment;
  final bool windows;
  final void Function(String command) _onNotApproved;
  final void Function() _onCouldNotRun;
  final ProcessStarter _start;
  final Future<void> Function(Process process) _killTree;
  final DateTime Function() _now;

  final _queue = <_Queued>[];
  final _running = <Process>{};
  final _timers = <Timer>{};

  /// Commands being started or running (never more than the limit).
  int _active = 0;
  final _last = <String, DateTime>{};
  final _told = <String>{};
  bool _couldNotRunTold = false;
  bool _disposed = false;

  /// Offers [e]. Never throws, never waits.
  void emit(AgentCommandEvent e) {
    if (_disposed) return;
    final command = _command();
    if (command.trim().isEmpty) return;
    final hash = commandHash(command);
    if (!_approved(hash)) {
      if (_told.add(hash)) _onNotApproved(command);
      return;
    }
    final key = '${e.pane}\u0000${e.event}';
    final now = _now();
    final before = _last[key];
    if (before != null && now.difference(before) < kAgentCommandGap) return;
    _last[key] = now;
    if (_last.length > 256) {
      _last.removeWhere((_, t) => now.difference(t) >= kAgentCommandGap);
    }
    // What was approved is what runs: the words are fixed now, not read
    // again when the event's turn comes (the file may have changed).
    final argv = splitCommand(command, home: home);
    if (argv == null ||
        !argvAllowed(argv, windows: windows) ||
        !programIsAbsolute(argv.first, windows: windows)) {
      _couldNotRun();
      return;
    }
    _queue.add(_Queued(e, hash, argv));
    while (_queue.length > kAgentCommandQueue) {
      _queue.removeAt(0);
    }
    _pump();
  }

  void _couldNotRun() {
    if (_couldNotRunTold) return;
    _couldNotRunTold = true;
    _onCouldNotRun();
  }

  void _pump() {
    while (!_disposed && _active < kAgentCommandParallel && _queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      _active++;
      unawaited(_run(item));
    }
  }

  Map<String, String> _childEnvironment(AgentCommandEvent e) => {
    for (final name in kAgentCommandEnvNames) name: ?_environment[name],
    ...e.env(),
  };

  Future<void> _run(_Queued item) async {
    final e = item.event;
    final argv = item.argv;
    try {
      // The user may have taken the permission back while it waited.
      if (!_approved(item.hash)) return;
      final Process process;
      try {
        process = await _start(
          argv.first,
          argv.skip(1).toList(),
          workingDirectory: home.isEmpty ? null : home,
          environment: _childEnvironment(e),
          includeParentEnvironment: false,
          runInShell: false,
        );
      } on Object {
        _couldNotRun();
        return;
      }
      if (_disposed) {
        process.kill(ProcessSignal.sigkill);
        return;
      }
      _running.add(process);
      // From the start, whatever the command does with its input.
      final timer = Timer(kAgentCommandTimeout, () => _kill(process));
      _timers.add(timer);
      // Output is read and dropped so the pipe never fills.
      unawaited(process.stdout.drain<void>().catchError((Object _) {}));
      unawaited(process.stderr.drain<void>().catchError((Object _) {}));
      // A command that does not read its input breaks the pipe: that is
      // its business, not an error of ours.
      unawaited(process.stdin.done.catchError((Object _) {}));
      unawaited(() async {
        try {
          process.stdin.writeln(e.jsonLine());
          await process.stdin.close();
        } on Object {
          // The command did not read its input: not our problem.
        }
      }());
      try {
        await process.exitCode;
      } on Object {
        // Gone.
      } finally {
        timer.cancel();
        _timers.remove(timer);
        _running.remove(process);
      }
    } finally {
      _active--;
      _pump();
    }
  }

  void _kill(Process process) => unawaited(_killTree(process));

  void dispose() {
    _disposed = true;
    _queue.clear();
    for (final t in _timers.toList()) {
      t.cancel();
    }
    _timers.clear();
    for (final p in _running.toList()) {
      _kill(p);
    }
  }

  @override
  String toString() => '…';
}

final class _Queued {
  const _Queued(this.event, this.hash, this.argv);
  final AgentCommandEvent event;

  /// The hash of the string that was approved when the event came in.
  final String hash;
  final List<String> argv;
}

/// How a process is started (tests replace it).
final agentCommandStarterProvider = Provider<ProcessStarter?>((_) => null);

/// How a process tree is stopped (tests replace it).
final agentCommandKillTreeProvider =
    Provider<Future<void> Function(Process process)?>((_) => null);

/// The window's one runner. The background service never has one: it has
/// no configuration and no status model, so a command runs once.
final agentCommandRunnerProvider = Provider<AgentCommandRunner>((ref) {
  final tabs = ref.read(terminalTabsProvider.notifier);
  final runner = AgentCommandRunner(
    command: () => ref.read(shellxConfigProvider).config.agentEventCommand,
    approved: (hash) =>
        isCommandApproved(ref.read(settingsStoreProvider), hash),
    home: ref.read(homeDirectoryProvider),
    environment: Platform.environment,
    windows: Platform.isWindows,
    start: ref.read(agentCommandStarterProvider),
    killTree: ref.read(agentCommandKillTreeProvider),
    onNotApproved: (command) =>
        tabs.showNotice(AgentCommandNotApprovedNotice(command)),
    onCouldNotRun: () => tabs.showNotice(const AgentCommandFailedNotice()),
  );
  ref.onDispose(runner.dispose);
  return runner;
});
