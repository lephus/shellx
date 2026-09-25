import 'dart:io';

import 'pty.dart';

/// Decides which shell a new session runs.
abstract interface class ShellResolver {
  Future<ShellCommand> resolve();
}

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Spec §7:
/// - macOS: the login shell from `dscl . -read /Users/<user> UserShell`,
///   started as a login shell (`-l`); `/bin/zsh -l` when it cannot be read.
/// - Windows: `pwsh.exe` when it is on PATH, otherwise `powershell.exe`.
/// - Any other OS (tests, CI): `/bin/sh`.
final class PlatformShellResolver implements ShellResolver {
  PlatformShellResolver({
    required String operatingSystem,
    required Map<String, String> environment,
    ProcessRunner? run,
    Future<bool> Function(String executable)? isOnPath,
  }) : _operatingSystem = operatingSystem,
       _environment = environment,
       _run = run ?? _runProcess,
       _isOnPath = isOnPath;

  static const ShellCommand macFallback = ShellCommand(
    executable: '/bin/zsh',
    arguments: ['-l'],
    name: 'zsh',
  );

  final String _operatingSystem;
  final Map<String, String> _environment;
  final ProcessRunner _run;
  final Future<bool> Function(String executable)? _isOnPath;

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments);

  @override
  Future<ShellCommand> resolve() async {
    switch (_operatingSystem) {
      case 'macos':
        return _resolveMac();
      case 'windows':
        final hasPwsh = await (_isOnPath ?? _searchPath)('pwsh.exe');
        return hasPwsh
            ? const ShellCommand(
                executable: 'pwsh.exe',
                arguments: [],
                name: 'pwsh',
              )
            : const ShellCommand(
                executable: 'powershell.exe',
                arguments: [],
                name: 'powershell',
              );
      default:
        return const ShellCommand(
          executable: '/bin/sh',
          arguments: [],
          name: 'sh',
        );
    }
  }

  Future<ShellCommand> _resolveMac() async {
    final user = _environment['USER'] ?? _environment['LOGNAME'];
    if (user == null || user.isEmpty) return macFallback;
    try {
      final result = await _run('dscl', [
        '.',
        '-read',
        '/Users/$user',
        'UserShell',
      ]);
      if (result.exitCode != 0) return macFallback;
      final shell = _parseUserShell('${result.stdout}');
      if (shell == null) return macFallback;
      return ShellCommand(
        executable: shell,
        arguments: const ['-l'],
        name: shell.split('/').last,
      );
    } catch (_) {
      return macFallback;
    }
  }

  /// Parses `UserShell: /bin/zsh` (value on the same line or on the next).
  static String? _parseUserShell(String output) {
    final lines = output.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('UserShell:')) continue;
      var value = line.substring('UserShell:'.length).trim();
      if (value.isEmpty && i + 1 < lines.length) value = lines[i + 1].trim();
      return value.startsWith('/') ? value : null;
    }
    return null;
  }

  Future<bool> _searchPath(String executable) async {
    final path = _environment['PATH'] ?? _environment['Path'] ?? '';
    for (final entry in path.split(';')) {
      final directory = entry.trim();
      if (directory.isEmpty) continue;
      final prefix = directory.endsWith(r'\') ? directory : '$directory\\';
      if (await File('$prefix$executable').exists()) return true;
    }
    return false;
  }
}
