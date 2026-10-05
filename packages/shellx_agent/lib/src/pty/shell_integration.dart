import 'dart:io';

import 'pty.dart';
import 'shell_hook_scripts.dart';

/// What to start: the (possibly changed) command and environment.
final class ShellLaunch {
  const ShellLaunch(this.command, this.environment);
  final ShellCommand command;
  final Map<String, String> environment;
}

/// Starts ShellX sessions' shells with a small hook that emits the OSC
/// sequences push notifications need (push spec §4.4), **without touching
/// the user's own startup files**:
///
/// - zsh: `ZDOTDIR` points at `<directory>/zsh`, whose `.zshenv` restores
///   the user's `ZDOTDIR` (passed in `SHELLX_USER_ZDOTDIR`) and sources the
///   user's `.zshenv`; the user's other startup files then load as usual.
/// - bash: `--rcfile <directory>/bash/rc.bash -i`, which sources the files
///   bash would have read (login files when the command was a login shell,
///   else `~/.bashrc`).
/// - PowerShell (`pwsh`, `powershell`): `-NoExit -Command` dot-sources
///   `<directory>/pwsh/hook.ps1` after the profiles.
/// - Anything else, a command with arguments the hook does not understand,
///   or a file that cannot be written: started unchanged (no command
///   notifications, nothing else lost).
///
/// The files are (re)written before every start when missing or stale, so
/// a cleaned temporary directory never leaves a shell without its startup
/// files. [directory] should be private to the user (e.g. the app's support
/// directory).
final class ShellIntegration {
  ShellIntegration({required String directory}) : _directory = directory;

  final String _directory;

  String get _sep => Platform.pathSeparator;

  ShellLaunch apply(ShellCommand command, Map<String, String> environment) {
    final unchanged = ShellLaunch(command, environment);
    try {
      return switch (_kind(command.executable)) {
            'zsh' => _zsh(command, environment),
            'bash' => _bash(command, environment),
            'pwsh' || 'powershell' => _powerShell(command, environment),
            _ => null,
          } ??
          unchanged;
    } on FileSystemException {
      return unchanged;
    }
  }

  static String _kind(String executable) {
    var name = executable.split(RegExp(r'[\\/]')).last.toLowerCase();
    if (name.endsWith('.exe')) name = name.substring(0, name.length - 4);
    if (name.startsWith('-')) name = name.substring(1);
    return name;
  }

  /// Only plain interactive/login starts are hooked (`-l`, `-i`, `--login`
  /// and their combinations); `-c`, scripts and other options are not.
  static bool _plainFlags(List<String> args, {required bool longLogin}) =>
      args.every(
        (a) => (longLogin && a == '--login') || RegExp(r'^-[il]+$').hasMatch(a),
      );

  static bool _isLogin(List<String> args) =>
      args.any((a) => a == '--login' || RegExp(r'^-[il]*l[il]*$').hasMatch(a));

  ShellLaunch? _zsh(ShellCommand command, Map<String, String> environment) {
    if (!_plainFlags(command.arguments, longLogin: true)) return null;
    final dir = '$_directory${_sep}zsh';
    _ensure('$dir$_sep.zshenv', zshHookEnv);
    final env = Map<String, String>.of(environment);
    final user = environment['ZDOTDIR'];
    env.remove('SHELLX_USER_ZDOTDIR');
    if (user != null) env['SHELLX_USER_ZDOTDIR'] = user;
    env['ZDOTDIR'] = dir;
    return ShellLaunch(command, env);
  }

  ShellLaunch? _bash(ShellCommand command, Map<String, String> environment) {
    final args = command.arguments;
    if (!_plainFlags(args, longLogin: true)) return null;
    final rc = '$_directory${_sep}bash${_sep}rc.bash';
    _ensure(rc, bashHookRc);
    final env = Map<String, String>.of(environment)
      ..remove('SHELLX_BASH_LOGIN');
    if (_isLogin(args)) env['SHELLX_BASH_LOGIN'] = '1';
    return ShellLaunch(
      ShellCommand(
        executable: command.executable,
        arguments: ['--rcfile', rc, '-i'],
        name: command.name,
      ),
      env,
    );
  }

  static const _powerShellPlain = {
    '-nologo',
    '-noprofileloadtime',
    '-login',
    '-l',
    '-noexit',
  };

  ShellLaunch? _powerShell(
    ShellCommand command,
    Map<String, String> environment,
  ) {
    final args = command.arguments;
    if (!args.every((a) => _powerShellPlain.contains(a.toLowerCase()))) {
      return null; // -Command, -File, -NoProfile, ...: left alone
    }
    final script = '$_directory${_sep}pwsh${_sep}hook.ps1';
    _ensure(script, powerShellHook);
    final quoted = script.replaceAll("'", "''");
    return ShellLaunch(
      ShellCommand(
        executable: command.executable,
        arguments: [
          ...args.where((a) => a.toLowerCase() != '-noexit'),
          '-NoExit',
          '-Command',
          "try { . '$quoted' } catch { }",
        ],
        name: command.name,
      ),
      environment,
    );
  }

  static void _ensure(String path, String content) {
    final file = File(path);
    if (file.existsSync() && file.readAsStringSync() == content) return;
    file.parent.createSync(recursive: true);
    final temp = File('$path.tmp$pid');
    temp.writeAsStringSync(content, flush: true);
    temp.renameSync(path);
  }
}
