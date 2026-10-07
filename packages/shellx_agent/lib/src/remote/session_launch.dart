import 'ssh_target.dart';

bool _hasControl(String text) =>
    text.runes.any((r) => r < 0x20 || r == 0x7F || (r >= 0x80 && r <= 0x9F));

/// A8 D25: tmux forbids `:` and `.` in session names.
bool isValidTmuxName(String name) =>
    name.isNotEmpty &&
    name.length <= 64 &&
    !name.contains(':') &&
    !name.contains('.') &&
    !_hasControl(name);

final _plainTmux = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// D11: names a hookless connection may pass to the server's shell as a
/// bare word (no quoting is involved there).
bool isPlainTmuxName(String name) => _plainTmux.hasMatch(name);

/// D14/D29: a folder on the server, as reported (`/…`) or typed (`~/…`).
bool isValidRemoteCwd(String path) =>
    path.isNotEmpty &&
    path.length <= 4096 &&
    !_hasControl(path) &&
    (path.startsWith('/') || path == '~' || path.startsWith('~/'));

/// What a new session runs instead of a local login shell (A8 D2). Saved in
/// the A5a layout, sent over the A5b socket and by the A7 CLI as [toJson];
/// whatever comes back is re-checked by [fromJson].
sealed class SessionLaunch {
  const SessionLaunch();

  /// The server; null for a tmux session on this computer.
  SshTarget? get host;

  /// [SshTarget.key] of [host], or '' (D5).
  String get hostLabel => host?.key ?? '';

  Map<String, Object?> toJson();

  /// D24: what a split of this pane starts, [cwd] being the pane's folder;
  /// null = a local shell.
  SessionLaunch? forSplit(String? cwd);

  /// Whether the bootstrap may write the ShellX hooks (D10/D11).
  bool get usesHook;

  /// The same launch with the hook switched on or off.
  SessionLaunch withHook(bool hook);

  /// D21: the same launch after a lost connection, in the last folder.
  SessionLaunch forReconnect(String? cwd);

  static SessionLaunch? fromJson(Object? json) {
    if (json is! Map) return null;
    final hook = json['hook'] ?? true;
    if (hook is! bool) return null;
    switch (json['kind']) {
      case 'ssh':
        final target = json['target'];
        final cwd = json['cwd'];
        if (target is! String) return null;
        final parsed = SshTarget.parseKey(target);
        if (parsed == null) return null;
        if (cwd != null && (cwd is! String || !isValidRemoteCwd(cwd))) {
          return null;
        }
        return SshLaunch(parsed, remoteCwd: cwd as String?, hook: hook);
      case 'tmux':
        final session = json['session'];
        final host = json['host'];
        final create = json['create'] ?? false;
        if (session is! String || !isValidTmuxName(session)) return null;
        if (create is! bool) return null;
        SshTarget? target;
        if (host != null) {
          if (host is! String) return null;
          target = SshTarget.parseKey(host);
          if (target == null) return null;
        }
        return TmuxLaunch(session, host: target, create: create, hook: hook);
      default:
        return null;
    }
  }
}

final class SshLaunch extends SessionLaunch {
  const SshLaunch(this.target, {this.remoteCwd, this.hook = true});

  final SshTarget target;

  /// Where the shell starts on the server; null = its home.
  final String? remoteCwd;

  /// D10/D11: the bootstrap writes the ShellX hooks on the server.
  final bool hook;

  @override
  bool get usesHook => hook;

  @override
  SshLaunch withHook(bool hook) =>
      SshLaunch(target, remoteCwd: remoteCwd, hook: hook);

  @override
  SshTarget get host => target;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'ssh',
    'target': target.key,
    if (remoteCwd != null) 'cwd': remoteCwd,
    'hook': hook,
  };

  @override
  SshLaunch forSplit(String? cwd) => SshLaunch(
    target,
    remoteCwd: cwd != null && isValidRemoteCwd(cwd) ? cwd : null,
    hook: hook,
  );

  @override
  SshLaunch forReconnect(String? cwd) => SshLaunch(
    target,
    remoteCwd: cwd != null && isValidRemoteCwd(cwd) ? cwd : remoteCwd,
    hook: hook,
  );

  @override
  bool operator ==(Object other) =>
      other is SshLaunch &&
      other.target == target &&
      other.remoteCwd == remoteCwd &&
      other.hook == hook;

  @override
  int get hashCode => Object.hash(target, remoteCwd, hook);

  @override
  String toString() => 'SshLaunch(…)';
}

final class TmuxLaunch extends SessionLaunch {
  const TmuxLaunch(
    this.session, {
    SshTarget? host,
    this.create = false,
    this.hook = true,
  }) : _host = host;

  final String session;
  final SshTarget? _host;

  /// `new-session -A` instead of `attach-session` (dialog "Create").
  final bool create;

  /// For a server: the bootstrap (without hook files) may run (D11).
  final bool hook;

  @override
  bool get usesHook => hook;

  @override
  TmuxLaunch withHook(bool hook) =>
      TmuxLaunch(session, host: _host, create: create, hook: hook);

  @override
  SshTarget? get host => _host;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'tmux',
    'session': session,
    if (_host != null) 'host': _host.key,
    if (create) 'create': true,
    'hook': hook,
  };

  @override
  SessionLaunch? forSplit(String? cwd) {
    final server = _host;
    return server == null ? null : SshLaunch(server, hook: hook);
  }

  @override
  TmuxLaunch forReconnect(String? cwd) =>
      TmuxLaunch(session, host: _host, hook: hook);

  @override
  bool operator ==(Object other) =>
      other is TmuxLaunch &&
      other.session == session &&
      other._host == _host &&
      other.create == create &&
      other.hook == hook;

  @override
  int get hashCode => Object.hash(session, _host, create, hook);

  @override
  String toString() => 'TmuxLaunch(…)';
}

/// What `SessionSummary.remote` says about a remote or tmux session.
final class SessionRemote {
  const SessionRemote({
    required this.launch,
    this.connected = false,
    this.home,
  });

  final SessionLaunch launch;

  /// D17: the server answered (OSC 6973 hello), or 10 s without the hook,
  /// or at once for a local tmux client.
  final bool connected;

  /// The server's `$HOME` (OSC 6973), to show `~`.
  final String? home;

  bool get isTmux => launch is TmuxLaunch;

  String? get tmuxSession => switch (launch) {
    TmuxLaunch(:final session) => session,
    SshLaunch() => null,
  };

  String? get hostKey => launch.host?.key;

  @override
  bool operator ==(Object other) =>
      other is SessionRemote &&
      other.launch == launch &&
      other.connected == connected &&
      other.home == home;

  @override
  int get hashCode => Object.hash(launch, connected, home);

  @override
  String toString() => 'SessionRemote(connected: $connected, …)';
}
