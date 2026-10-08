import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../terminal/agent_status.dart' show AgentKind;

// A12 D6, D23: what Settings › Agents shows about each agent's hooks. It
// READS the agent's own file to tell "installed" from "not installed", the
// same question `shellx integrations status` answers, and nothing else: the
// app never writes an agent's configuration (the user's files are theirs,
// D7). Installing and removing happen in a terminal tab, where the CLI shows
// the diff and asks. Never logs a path or any of the file's content.

/// The CLI refuses an agent file over this size, so it is "not installed"
/// here too.
const int kIntegrationFileMax = 1 << 20;

/// How the probe sees the disk (a fake in tests). Reads and existence only:
/// there is no way to write through it.
abstract interface class IntegrationFs {
  /// The text of [path]; null for a file that is absent, unreadable, not
  /// UTF-8 text or larger than [kIntegrationFileMax]. Never throws.
  Future<String?> readText(String path);

  /// Whether [path] (a file or a folder) exists. Never throws.
  Future<bool> exists(String path);
}

final class DiskIntegrationFs implements IntegrationFs {
  const DiskIntegrationFs();

  @override
  Future<String?> readText(String path) async {
    try {
      final file = File(path);
      if (await file.length() > kIntegrationFileMax) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length > kIntegrationFileMax) return null;
      return utf8.decode(bytes);
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> exists(String path) async {
    try {
      return await FileSystemEntity.type(path) != FileSystemEntityType.notFound;
    } on Object {
      return false;
    }
  }
}

/// One agent's integration as the probe found it.
@immutable
final class IntegrationStatus {
  const IntegrationStatus(
    this.agent, {
    required this.installed,
    this.notFound = false,
  });
  final AgentKind agent;

  /// ShellX's hooks are in the agent's file.
  final bool installed;

  /// Neither the agent's folder nor its program is anywhere the probe
  /// looks. A GUI app does not see the shell's PATH, so this is said only
  /// when both signals agree, and never on Windows.
  final bool notFound;

  @override
  String toString() => '…';
}

/// The five events whose hooks make a Claude Code or Gemini CLI install
/// (spec D6; the command of each is `shellx agent-event <agent> <event>`).
const _hookEvents = [
  'session-start',
  'prompt-submit',
  'notification',
  'stop',
  'session-end',
];

const _codexNotify =
    'notify = ["shellx", "agent-event", "codex", "turn-complete"]';
const _openCodeMarker = '// shellx-agent-integration';

/// The words `shellx integrations install|uninstall <agent>` takes: fixed
/// words and a name from the closed set, never user text. Consent happens in
/// the CLI (no `--yes`).
String integrationCommand(AgentKind agent, {required bool remove}) =>
    'shellx integrations ${remove ? 'uninstall' : 'install'} ${agent.name}';

final class IntegrationProbe {
  IntegrationProbe({
    required this.fs,
    required Map<String, String> env,
    required this.home,
    this.windows = false,
  }) : _env = env,
       _path = p.Context(style: windows ? p.Style.windows : p.Style.posix);

  final IntegrationFs fs;
  final String home;
  final bool windows;
  final Map<String, String> _env;
  final p.Context _path;

  String? _var(String key) {
    final v = _env[key];
    return v == null || v.isEmpty ? null : v;
  }

  /// The agent's folder and the file the CLI looks at (`config_path` of
  /// the CLI); null when the home folder is unknown and nothing says where.
  ({String dir, String file})? _where(AgentKind a) {
    String? dir(String? override, List<String> fallback) =>
        override ?? (home.isEmpty ? null : _path.joinAll([home, ...fallback]));

    final (String? folder, List<String> file) = switch (a) {
      AgentKind.claude => (
        dir(_var('CLAUDE_CONFIG_DIR'), ['.claude']),
        ['settings.json'],
      ),
      AgentKind.codex => (dir(_var('CODEX_HOME'), ['.codex']), ['config.toml']),
      AgentKind.gemini => (dir(null, ['.gemini']), ['settings.json']),
      AgentKind.opencode => (
        dir(_var('OPENCODE_CONFIG_DIR'), ['.config', 'opencode']),
        ['plugins', 'shellx-agent.js'],
      ),
    };
    if (folder == null) return null;
    return (dir: folder, file: _path.joinAll([folder, ...file]));
  }

  bool _isInstalled(AgentKind a, String? text) {
    if (text == null) return false;
    switch (a) {
      case AgentKind.claude || AgentKind.gemini:
        return _hookEvents.every(
          (e) => text.contains('shellx agent-event ${a.name} $e'),
        );
      case AgentKind.codex:
        return text.split('\n').any((l) => l.trim() == _codexNotify);
      case AgentKind.opencode:
        return text.startsWith(_openCodeMarker);
    }
  }

  /// Folders a program the agent installs is usually in (macOS and Linux).
  List<String> get _programFolders => [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    _path.join(home, '.local', 'bin'),
    _path.join(home, '.claude', 'local'),
    _path.join(home, '.npm-global', 'bin'),
  ];

  Future<bool> _programFound(AgentKind a) async {
    for (final folder in _programFolders) {
      if (await fs.exists(_path.join(folder, a.name))) return true;
    }
    return false;
  }

  Future<IntegrationStatus> _one(AgentKind a) async {
    final where = _where(a);
    if (where == null) return IntegrationStatus(a, installed: false);
    String? text;
    try {
      text = await fs.readText(where.file);
    } on Object {
      text = null; // a fake or a bug: the same as unreadable
    }
    final installed = _isInstalled(a, text);
    var notFound = false;
    if (!installed && !windows && home.isNotEmpty) {
      try {
        notFound = !await fs.exists(where.dir) && !await _programFound(a);
      } on Object {
        notFound = false;
      }
    }
    return IntegrationStatus(a, installed: installed, notFound: notFound);
  }

  Future<Map<AgentKind, IntegrationStatus>> probe() async => {
    for (final a in AgentKind.values) a: await _one(a),
  };
}
