import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Where an environment came from.
enum LoginEnvSource { interactiveLogin, login, process }

/// The environment agents and git run with (spec D6).
final class LoginEnv {
  const LoginEnv(this.vars, {required this.source});

  final Map<String, String> vars;
  final LoginEnvSource source;

  @override
  String toString() => 'LoginEnv(${source.name}, ${vars.length} vars)';
}

/// Runs [shell] with [args]; returns its exit code and stdout, or throws
/// [TimeoutException] after [timeout].
typedef ShellRunner =
    Future<(int, List<int>)> Function(
      String shell,
      List<String> args,
      Map<String, String> environment,
      Duration timeout,
    );

/// The `KEY=value` pairs (`env -0`: NUL-separated) between the first and
/// the last `\x1e` of [stdout]; null without both markers.
Map<String, String>? parseMarkedEnv(List<int> stdout) {
  final text = utf8.decode(stdout, allowMalformed: true);
  final start = text.indexOf('\x1e');
  final end = text.lastIndexOf('\x1e');
  if (start < 0 || end <= start) return null;
  final vars = <String, String>{};
  for (final entry in text.substring(start + 1, end).split('\x00')) {
    final eq = entry.indexOf('=');
    if (eq <= 0) continue;
    vars[entry.substring(0, eq)] = entry.substring(eq + 1);
  }
  return vars;
}

const _dropped = {'PWD', 'OLDPWD', 'SHLVL', '_'};

/// [env] without ShellX's own variables (no `SHELLX_CLI_TOKEN`, spec D6)
/// and per-shell noise. The agent's cwd is set apart.
Map<String, String> cleanAgentEnv(Map<String, String> env) => {
  for (final e in env.entries)
    if (!e.key.toUpperCase().startsWith('SHELLX_') && !_dropped.contains(e.key))
      e.key: e.value,
};

/// The user's login-shell environment, resolved once per app session
/// (spec D6): `$SHELL -i -l -c`, then `-l -c`, then the app's own
/// environment. The script prints `env -0` between `\x1e` markers, so
/// whatever a profile prints around it is ignored. Windows has no login
/// shell: the app's environment is used. Agents never run through a shell.
final class LoginShellEnv {
  LoginShellEnv({
    String? shell,
    Map<String, String>? processEnv,
    bool? isWindows,
    bool? isMacOS,
    ShellRunner? run,
    this.timeout = const Duration(seconds: 10),
  }) : _processEnv = processEnv ?? Platform.environment,
       _isWindows = isWindows ?? Platform.isWindows,
       _shell =
           shell ??
           _pickShell(
             (processEnv ?? Platform.environment)['SHELL'],
             isMacOS ?? Platform.isMacOS,
           ),
       _run = run ?? _runShell;

  static const script = r"printf '\036'; /usr/bin/env -0; printf '\036'";
  static const _known = {'zsh', 'bash', 'sh', 'fish', 'dash', 'ksh'};

  final Duration timeout;
  final Map<String, String> _processEnv;
  final bool _isWindows;
  final String _shell;
  final ShellRunner _run;
  Future<LoginEnv>? _cached;

  Future<LoginEnv> resolve() => _cached ??= _resolve();

  /// Forgets the environment (the user installed Node, edited a profile…).
  void invalidate() => _cached = null;

  static String _pickShell(String? shell, bool isMacOS) {
    if (shell != null &&
        shell.startsWith('/') &&
        _known.contains(shell.split('/').last)) {
      return shell;
    }
    return isMacOS ? '/bin/zsh' : '/bin/sh';
  }

  Future<LoginEnv> _resolve() async {
    if (_isWindows) {
      return LoginEnv(
        cleanAgentEnv(_processEnv),
        source: LoginEnvSource.process,
      );
    }
    // A profile can skip slow setup when it sees this (like VS Code's flag);
    // cleanAgentEnv drops it again.
    final env = {
      ..._processEnv,
      'SHELLX_RESOLVING_ENVIRONMENT': '1',
      'TERM': 'dumb',
    };
    for (final (args, source) in [
      (['-i', '-l', '-c', script], LoginEnvSource.interactiveLogin),
      (['-l', '-c', script], LoginEnvSource.login),
    ]) {
      try {
        final (_, out) = await _run(_shell, args, env, timeout);
        final vars = parseMarkedEnv(out);
        if (vars != null && vars['PATH'] != null) {
          return LoginEnv(cleanAgentEnv(vars), source: source);
        }
      } on Object {
        // Try the next way.
      }
    }
    return LoginEnv(cleanAgentEnv(_processEnv), source: LoginEnvSource.process);
  }

  static Future<(int, List<int>)> _runShell(
    String shell,
    List<String> args,
    Map<String, String> environment,
    Duration timeout,
  ) async {
    final process = await Process.start(
      shell,
      args,
      environment: environment,
      includeParentEnvironment: false,
    );
    unawaited(process.stdin.close().then<void>((_) {}, onError: (Object _) {}));
    unawaited(process.stderr.drain<void>());
    final out = <int>[];
    final outDone = process.stdout.listen(out.addAll).asFuture<void>();
    try {
      final code = await process.exitCode.timeout(timeout);
      // A background child may keep stdout open; the markers are in by now.
      await outDone.timeout(const Duration(seconds: 1), onTimeout: () {});
      return (code, out);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }
}
