import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../remote/remote_state.dart';
import '../remote/ssh_actions.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'cli_fields.dart';
import 'cli_targets.dart';
import 'ui_pane_io.dart' show kCmdMaxBytes;

/// Opens a tab the way the handler's `_opening` does (D33: waits its turn,
/// maps the tab list's failures to wire codes). [open] runs afresh on every
/// try.
typedef CliOpening = Future<int> Function(Future<int> Function() open);

/// How long a tmux listing may take before it is `tmux_failed`: a server
/// that never answers must not hang the command line.
const Duration kTmuxListBound = Duration(seconds: 8);

/// A8 D22, D33: `ui.ssh.open`, `ui.tmux.list`, `ui.tmux.attach` on
/// [SshActions]. Everything a script sends (server, folder, tmux name) is
/// checked here before anything runs, and goes to ssh as argv only.
///
/// Never logs request contents (servers, folders, commands, session names).
final class SshCommands {
  SshCommands(this._ref, {this.tmuxBound = kTmuxListBound});

  final Ref _ref;
  final Duration tmuxBound;

  SshActions get _ssh => _ref.read(sshActionsProvider);
  SidebarState get _sideState => _ref.read(sidebarWorkspacesProvider);
  SidebarWorkspaces get _side => _ref.read(sidebarWorkspacesProvider.notifier);

  SshTarget _target(MuxMessage r, String key) {
    final text = stringField(r, key, max: 255);
    final target = text == null ? null : SshTarget.parse(text);
    if (target == null) {
      throw badRequest('$key must be a server (alias or user@host:port)');
    }
    return target;
  }

  SshTarget? _optionalTarget(MuxMessage r, String key) =>
      r.fields[key] == null ? null : _target(r, key);

  /// The server path of `--cwd`: absolute or under `~`.
  String? remoteCwd(MuxMessage r) {
    final cwd = stringField(r, 'cwd');
    if (cwd != null && !isValidRemoteCwd(cwd)) {
      throw badRequest('cwd must be a folder on the server: / or ~/');
    }
    return cwd;
  }

  /// `{tab, pane}` of a new tab on a server. [typeCommand] is the window's
  /// `--cmd` path (types once the remote shell is ready, D32).
  Future<Map<String, Object?>> open(
    MuxMessage r,
    CliOpening opening,
    void Function(int tab, String cmd)? typeCommand,
  ) async {
    final target = _target(r, 'target');
    final cwd = remoteCwd(r);
    final cmd = textField(r, 'cmd', maxBytes: kCmdMaxBytes, limit: '16 KiB');
    final key = stringField(r, 'workspace');
    final hook = r.fields['hook'];
    if (hook != null && hook is! bool) {
      throw badRequest('hook must be true or false');
    }
    final focus = flagField(r, 'focus');
    final tab = await opening(
      () => _remote(
        () => _ssh.connectForCli(
          target,
          // Resolved on every try: one deleted while waiting is not_found.
          workspaceId: key == null
              ? null
              : resolveWorkspace(_sideState, key, _side.displayName),
          remoteCwd: cwd,
          hook: hook != false,
          select: focus,
        ),
      ),
    );
    if (focus) _side.reveal(tab);
    if (cmd != null) typeCommand?.call(tab, cmd);
    return {'tab': tab, 'pane': tab};
  }

  Future<Map<String, Object?>> list(MuxMessage r) async {
    final host = _optionalTarget(r, 'host');
    final TmuxListResult result;
    try {
      result = await _ssh.listTmux(host).timeout(tmuxBound);
    } on TimeoutException {
      throw const CliFailure(
        CliError.tmuxFailed,
        'could not list tmux sessions in time',
      );
    }
    return switch (result) {
      TmuxSessions(:final sessions) => {
        'sessions': [
          for (final s in sessions)
            {
              'name': s.name,
              'windows': s.windows,
              'attached': s.attached,
              if (s.activity != null)
                'activity': s.activity!.millisecondsSinceEpoch ~/ 1000,
            },
        ],
      },
      TmuxUnavailable() => throw const CliFailure(
        CliError.tmuxUnavailable,
        'tmux is not installed there',
      ),
      TmuxListFailed(:final reason) => throw CliFailure(
        CliError.tmuxFailed,
        reason == TmuxListFailure.auth
            ? 'the server wants a password: connect once with shellx ssh'
            : 'could not list tmux sessions',
      ),
    };
  }

  Future<Map<String, Object?>> attach(MuxMessage r, CliOpening opening) async {
    final name = stringField(r, 'name', max: 64);
    if (name == null || !isValidTmuxName(name)) {
      throw badRequest('name: 1-64 characters, no ":" or "."');
    }
    final host = _optionalTarget(r, 'host');
    final create = flagField(r, 'create');
    final focus = flagField(r, 'focus');
    final tab = await opening(
      () => _remote(
        () => _ssh.attachTmuxForCli(
          name,
          host: host,
          create: create,
          select: focus,
        ),
      ),
    );
    if (focus) _side.reveal(tab);
    return {'tab': tab, 'pane': tab};
  }

  /// D33: the A8 spawn failures by name; any other is left to [opening].
  Future<T> _remote<T>(Future<T> Function() open) async {
    try {
      return await open();
    } on SpawnFailedException catch (e) {
      switch (e.message) {
        case 'ssh_unavailable':
          throw const CliFailure(
            CliError.sshUnavailable,
            'ssh is not installed on this computer',
          );
        case 'tmux_unavailable':
          throw const CliFailure(
            CliError.tmuxUnavailable,
            'tmux is not installed on this computer',
          );
      }
      rethrow;
    }
  }
}

/// A8 D22: `remote` of a pane in `ui.ls` (absent for a local shell): where
/// it really runs and whether it is still connected.
Map<String, Object?>? remoteOf(PaneSession pane) {
  final remote = pane.remote;
  if (remote == null) return null;
  return {
    'kind': remote.isTmux ? 'tmux' : 'ssh',
    'host': ?remote.hostKey,
    'tmux': ?remote.tmuxSession,
    'state': (pane.remoteState ?? RemoteState.connected).name,
  };
}
