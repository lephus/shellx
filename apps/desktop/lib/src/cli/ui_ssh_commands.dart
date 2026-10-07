import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../remote/remote_state.dart';
import '../remote/ssh_actions.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'cli_fields.dart';
import 'cli_targets.dart';
import 'ui_pane_io.dart' show PaneIoCommands, kCmdMaxBytes;

/// Opens a tab the way the handler's `_opening` does (D33: waits its turn,
/// maps the tab list's failures to wire codes). [open] runs afresh on every
/// try.
typedef CliOpening = Future<int> Function(Future<int> Function() open);

/// How long a tmux listing may take before it is `tmux_failed`: a server
/// that never answers must not hang the command line.
const Duration kTmuxListBound = Duration(seconds: 8);

/// Why `--cmd` needs the hook on a server.
const String kCmdNeedsHook = '--cmd needs the server hook';

/// How long a `--cmd` for a server pane waits for the server shell's hello.
const Duration kHelloWait = Duration(seconds: 60);

/// Types a command into a server pane only after its remote hook said
/// hello (the shell is up; no sign-in prompt is waiting for a password or
/// a host-key answer). No quiet or time fallbacks: a slow prompt must never
/// receive the command. Drops it silently when the pane ends or is
/// replaced, or when no hello comes within [wait]. [view] is null once the
/// pane is gone.
void typeWhenHello({
  required Stream<void> changes,
  required ({bool exited, bool connected})? Function() view,
  required void Function() type,
  Duration wait = kHelloWait,
}) {
  StreamSubscription<void>? sub;
  Timer? timer;
  var done = false;
  void finish() {
    done = true;
    timer?.cancel();
    unawaited(sub?.cancel());
  }

  void check() {
    if (done) return;
    final v = view();
    if (v == null || v.exited) return finish();
    if (v.connected) {
      finish();
      type();
    }
  }

  sub = changes.listen((_) => check());
  timer = Timer(wait, finish);
  check();
}

/// A8 D22, D33: `ui.ssh.open`, `ui.tmux.list`, `ui.tmux.attach` on
/// [SshActions]. Everything a script sends (server, folder, tmux name) is
/// checked here before anything runs, and goes to ssh as argv only.
///
/// Never logs request contents (servers, folders, commands, session names).
final class SshCommands {
  SshCommands(this._ref, this._io, {this.tmuxBound = kTmuxListBound});

  final Ref _ref;
  final PaneIoCommands _io;
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

  /// Types [cmd] into server pane [pane] after the hello, once.
  void typeOnServer(int pane, String cmd) {
    final tabs = _ref.read(terminalTabsProvider);
    if (tabs.tabOfSession(pane) == null) return;
    late final StreamController<void> changes;
    ProviderSubscription<TerminalTabsState>? sub;
    changes = StreamController<void>(
      sync: true,
      onListen: () =>
          sub = _ref.listen(terminalTabsProvider, (_, _) => changes.add(null)),
      onCancel: () => sub?.close(),
    );
    typeWhenHello(
      changes: changes.stream,
      view: () {
        final p = _ref
            .read(terminalTabsProvider)
            .tabOfSession(pane)
            ?.panes[pane];
        if (p == null) return null;
        return (exited: p.exited, connected: p.remote?.connected ?? false);
      },
      type: () => _io.typeNow(pane, cmd),
    );
  }

  /// `{tab, pane}` of a new tab on a server; `--cmd` waits for the hello.
  Future<Map<String, Object?>> open(MuxMessage r, CliOpening opening) async {
    final target = _target(r, 'target');
    final cwd = remoteCwd(r);
    final cmd = textField(r, 'cmd', maxBytes: kCmdMaxBytes, limit: '16 KiB');
    final key = stringField(r, 'workspace');
    final hook = r.fields['hook'];
    if (hook != null && hook is! bool) {
      throw badRequest('hook must be true or false');
    }
    final focus = flagField(r, 'focus');
    // The setting may switch the hook off for this server too.
    if (cmd != null && !(hook != false && _ssh.hookFor(target.key))) {
      throw badRequest(kCmdNeedsHook);
    }
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
    if (cmd != null) typeOnServer(tab, cmd);
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
