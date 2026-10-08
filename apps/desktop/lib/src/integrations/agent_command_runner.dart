import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart' show sha256Bytes;
import 'package:shellx_core/shellx_core.dart' show bytesToHex;

import '../config/config_controller.dart' show shellxConfigProvider;
import '../platform/settings_store.dart';
import '../terminal/local_sessions_provider.dart' show homeDirectoryProvider;
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import '../terminal/terminal_tabs.dart';

/// A12 D17 limits.
const Duration kAgentCommandTimeout = Duration(seconds: 10);
const int kAgentCommandParallel = 4;
const int kAgentCommandQueue = 16;
const Duration kAgentCommandGap = Duration(seconds: 1);

/// The longest `agent-event-command` string (also checked by the loader).
const int kAgentCommandMaxLength = 4096;
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

/// Every control character but the tab (a word separator).
final RegExp _control = RegExp(r'[\u0000-\u0008\u000a-\u001f\u007f]');

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

/// A small word splitter, not a shell: whitespace separates words; single
/// quotes keep everything; double quotes keep everything but `\"` and `\\`;
/// outside quotes a backslash escapes the next character. `$`, backticks,
/// globs and operators are ordinary characters. A word that starts with an
/// unquoted `~/` begins at [home]. Null: empty, an unbalanced quote, a
/// trailing backslash, or a control character anywhere.
List<String>? splitCommand(String input, {required String home}) {
  if (input.length > kAgentCommandMaxLength || _control.hasMatch(input)) {
    return null;
  }
  final words = <String>[];
  final word = StringBuffer();
  var inWord = false;
  var tilde = false; // the word began with an unquoted `~/`
  var index = 0;
  final n = input.length;

  void end() {
    if (!inWord) return;
    var text = word.toString();
    if (tilde && home.isNotEmpty) {
      text = home.endsWith('/')
          ? '$home${text.substring(2)}'
          : '$home${text.substring(1)}';
    }
    words.add(text);
    word.clear();
    inWord = false;
    tilde = false;
  }

  while (index < n) {
    final c = input[index];
    if (c == ' ' || c == '\t') {
      end();
      index++;
    } else if (c == "'") {
      final close = input.indexOf("'", index + 1);
      if (close < 0) return null;
      inWord = true;
      word.write(input.substring(index + 1, close));
      index = close + 1;
    } else if (c == '"') {
      inWord = true;
      index++;
      var closed = false;
      while (index < n) {
        final d = input[index];
        if (d == '"') {
          closed = true;
          index++;
          break;
        }
        if (d == r'\' &&
            index + 1 < n &&
            (input[index + 1] == '"' || input[index + 1] == r'\')) {
          word.write(input[index + 1]);
          index += 2;
        } else {
          word.write(d);
          index++;
        }
      }
      if (!closed) return null;
    } else if (c == r'\') {
      if (index + 1 >= n) return null;
      inWord = true;
      word.write(input[index + 1]);
      index += 2;
    } else {
      if (!inWord && c == '~' && index + 1 < n && input[index + 1] == '/') {
        tilde = true;
      }
      inWord = true;
      word.write(c);
      index++;
    }
  }
  end();
  return words.isEmpty ? null : words;
}

/// Windows has no shell here, so only a program that can start without one:
/// an `.exe`, or PowerShell with `-File`. Elsewhere any non-empty program.
bool argvAllowed(List<String> argv, {required bool windows}) {
  if (argv.isEmpty || argv.first.isEmpty) return false;
  if (!windows) return true;
  final exe = argv.first.toLowerCase();
  const shells = {'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe'};
  if (shells.contains(exe)) {
    return argv.length >= 3 && argv[1].toLowerCase() == '-file';
  }
  return exe.endsWith('.exe');
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
    DateTime Function()? now,
  }) : _command = command,
       _approved = approved,
       _environment = environment,
       _onNotApproved = onNotApproved,
       _onCouldNotRun = onCouldNotRun,
       _start = start ?? Process.start,
       _now = now ?? DateTime.now;

  final String Function() _command;
  final bool Function(String hash) _approved;
  final String home;
  final Map<String, String> _environment;
  final bool windows;
  final void Function(String command) _onNotApproved;
  final void Function() _onCouldNotRun;
  final ProcessStarter _start;
  final DateTime Function() _now;

  final _queue = <AgentCommandEvent>[];
  final _running = <Process>{};

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
    _queue.add(e);
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
      final e = _queue.removeAt(0);
      _active++;
      unawaited(_run(e));
    }
  }

  Map<String, String> _childEnvironment(AgentCommandEvent e) => {
    for (final name in kAgentCommandEnvNames) name: ?_environment[name],
    ...e.env(),
  };

  Future<void> _run(AgentCommandEvent e) async {
    try {
      final argv = splitCommand(_command(), home: home);
      if (argv == null || !argvAllowed(argv, windows: windows)) {
        _couldNotRun();
        return;
      }
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
      // Output is read and dropped so the pipe never fills.
      unawaited(process.stdout.drain<void>().catchError((Object _) {}));
      unawaited(process.stderr.drain<void>().catchError((Object _) {}));
      // A command that does not read its input breaks the pipe: that is
      // its business, not an error of ours.
      unawaited(process.stdin.done.catchError((Object _) {}));
      try {
        process.stdin.writeln(e.jsonLine());
        await process.stdin.close();
      } on Object {
        // The command did not read its input: not our problem.
      }
      final timer = Timer(kAgentCommandTimeout, () => _kill(process));
      try {
        await process.exitCode;
      } on Object {
        // Gone.
      } finally {
        timer.cancel();
        _running.remove(process);
      }
    } finally {
      _active--;
      _pump();
    }
  }

  void _kill(Process process) {
    if (windows) {
      // The tree, not just the parent.
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
  }

  void dispose() {
    _disposed = true;
    _queue.clear();
    for (final p in _running.toList()) {
      _kill(p);
    }
  }

  @override
  String toString() => '…';
}

/// How a process is started (tests replace it).
final agentCommandStarterProvider = Provider<ProcessStarter?>((_) => null);

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
    onNotApproved: (command) =>
        tabs.showNotice(AgentCommandNotApprovedNotice(command)),
    onCouldNotRun: () => tabs.showNotice(const AgentCommandFailedNotice()),
  );
  ref.onDispose(runner.dispose);
  return runner;
});
