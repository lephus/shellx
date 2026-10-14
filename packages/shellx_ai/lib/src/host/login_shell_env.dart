import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'probe.dart' show envValue, runProbe;

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

/// Where Windows keeps the user's environment variables (`reg query`).
const windowsUserEnvKey = r'HKCU\Environment';

/// Where Windows keeps the machine's environment variables (`reg query`).
const windowsMachineEnvKey =
    r'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

/// What `reg query <key> /v Path` printed for [key]; null when it could not
/// be had (no such value, no `reg`).
typedef RegistryReader = Future<String?> Function(String key);

/// The real [RegistryReader].
Future<String?> readRegistryPath(String key) async {
  final r = await runProbe('reg', ['query', key, '/v', 'Path']);
  return r == null || r.exitCode != 0 ? null : r.stdout;
}

final _regValue = RegExp(r'^\s*(\S+)\s+(REG_SZ|REG_EXPAND_SZ)\s+(.*?)\s*$');

/// The `Path` value in the output of `reg query <key> /v Path`
/// (`    Path    REG_EXPAND_SZ    <data>`): its data, and whether it holds
/// `%VAR%`s to expand (`REG_EXPAND_SZ`). Null when the output has no such
/// value: an error, another name or type, anything else.
({String data, bool expands})? parseRegQueryPath(String output) {
  for (final line in const LineSplitter().convert(output)) {
    final m = _regValue.firstMatch(line);
    if (m == null || m[1]!.toLowerCase() != 'path') continue;
    return (data: m[3]!, expands: m[2] == 'REG_EXPAND_SZ');
  }
  return null;
}

/// [text] with every `%NAME%` replaced by [vars]' NAME (without case, as on
/// Windows). A name it does not know stays as written; what a name expands to
/// is not expanded again.
String expandWindowsVars(String text, Map<String, String> vars) =>
    text.replaceAllMapped(
      RegExp(r'%([^%]+)%'),
      (m) => envValue(vars, m[1]!) ?? m[0]!,
    );

/// `PATH` as a fresh login would have it, from the registry's answers
/// ([machine] and [user]: the output of `reg query … /v Path`): the machine's
/// entries, then the user's, `%VAR%`s expanded from [vars] where the value is
/// `REG_EXPAND_SZ`. The entries of [vars]' own `PATH` that the registry lacks
/// follow (an app started from a shell keeps what that shell added), and an
/// entry is listed once, without case and with or without a final `\`. Null
/// when neither answer holds a `Path`.
String? mergeRegistryPath({
  String? machine,
  String? user,
  required Map<String, String> vars,
}) {
  final entries = <String>[];
  var found = false;
  for (final output in [machine, user]) {
    final value = output == null ? null : parseRegQueryPath(output);
    if (value == null) continue;
    found = true;
    final data = value.expands
        ? expandWindowsVars(value.data, vars)
        : value.data;
    entries.addAll(data.split(';'));
  }
  if (!found) return null;
  entries.addAll((envValue(vars, 'PATH') ?? '').split(';'));
  final seen = <String>{};
  final merged = <String>[];
  for (final raw in entries) {
    final entry = raw.trim();
    if (entry.isEmpty) continue;
    var key = entry.toLowerCase();
    while (key.length > 1 && (key.endsWith(r'\') || key.endsWith('/'))) {
      key = key.substring(0, key.length - 1);
    }
    if (seen.add(key)) merged.add(entry);
  }
  return merged.join(';');
}

/// The user's login-shell environment, resolved once per app session
/// (spec D6): `$SHELL -i -l -c`, then `-l -c`, then the app's own
/// environment. The script prints `env -0` between `\x1e` markers, so
/// whatever a profile prints around it is ignored. Windows has no login
/// shell: the app's environment is used, and after [invalidate] its `PATH` is
/// read again from the registry, so a Node installed since the app started is
/// found without restarting it. Agents never run through a shell.
final class LoginShellEnv {
  LoginShellEnv({
    String? shell,
    Map<String, String>? processEnv,
    bool? isWindows,
    bool? isMacOS,
    ShellRunner? run,
    RegistryReader? registry,
    this.timeout = const Duration(seconds: 10),
  }) : _processEnv = processEnv ?? Platform.environment,
       _isWindows = isWindows ?? Platform.isWindows,
       _shell =
           shell ??
           _pickShell(
             (processEnv ?? Platform.environment)['SHELL'],
             isMacOS ?? Platform.isMacOS,
           ),
       _run = run ?? _runShell,
       _registry = registry ?? readRegistryPath;

  static const script = r"printf '\036'; /usr/bin/env -0; printf '\036'";
  static const _known = {'zsh', 'bash', 'sh', 'fish', 'dash', 'ksh'};

  final Duration timeout;
  final Map<String, String> _processEnv;
  final bool _isWindows;
  final String _shell;
  final ShellRunner _run;
  final RegistryReader _registry;
  Future<LoginEnv>? _cached;

  /// The next resolve on Windows reads `PATH` from the registry.
  var _readRegistry = false;

  Future<LoginEnv> resolve() => _cached ??= _resolve();

  /// Forgets the environment (the user installed Node, edited a profile…).
  /// On Windows the next [resolve] also rebuilds `PATH` from the registry
  /// (V2-1 final review I-4); any failure there keeps the app's own.
  void invalidate() {
    _cached = null;
    if (_isWindows) _readRegistry = true;
  }

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
      final fromRegistry = _readRegistry;
      _readRegistry = false;
      return _resolveWindows(fromRegistry);
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

  Future<LoginEnv> _resolveWindows(bool fromRegistry) async {
    final env = cleanAgentEnv(_processEnv);
    if (fromRegistry) {
      final path = await _registryPath(env);
      if (path != null) {
        final key = env.keys.firstWhere(
          (k) => k.toUpperCase() == 'PATH',
          orElse: () => 'Path',
        );
        env[key] = path;
      }
    }
    return LoginEnv(env, source: LoginEnvSource.process);
  }

  /// `PATH` as the registry has it now ([mergeRegistryPath]); null when
  /// neither key answered, whatever the reason.
  Future<String?> _registryPath(Map<String, String> env) async {
    Future<String?> read(String key) async {
      try {
        return await _registry(key);
      } on Object {
        return null;
      }
    }

    final [machine, user] = await Future.wait([
      read(windowsMachineEnvKey),
      read(windowsUserEnvKey),
    ]);
    try {
      return mergeRegistryPath(machine: machine, user: user, vars: env);
    } on Object {
      return null;
    }
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
