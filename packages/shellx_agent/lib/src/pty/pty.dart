import 'dart:typed_data';

/// A pseudo-terminal running one shell process.
///
/// Adapter contract (desktop `flutter_pty` adapter and [ProcessPtyFactory]):
/// - [output] is a single-subscription stream that is closed (done) when the
///   process exits;
/// - [exitCode] completes once the process has exited;
/// - [kill] terminates the whole process tree.
abstract interface class Pty {
  Stream<Uint8List> get output;
  Future<int> get exitCode;
  void write(Uint8List data);
  void resize(int cols, int rows);
  void kill();
}

/// The shell to start for a new session.
final class ShellCommand {
  const ShellCommand({
    required this.executable,
    required this.arguments,
    required this.name,
  });

  final String executable;
  final List<String> arguments;

  /// Short display name used in tab titles, e.g. "zsh" or "pwsh".
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ShellCommand &&
      other.executable == executable &&
      other.name == name &&
      other.arguments.length == arguments.length &&
      Iterable<int>.generate(
        arguments.length,
      ).every((i) => other.arguments[i] == arguments[i]);

  @override
  int get hashCode => Object.hash(executable, name, Object.hashAll(arguments));

  @override
  String toString() => 'ShellCommand($executable ${arguments.join(' ')})';
}

/// Starts [Pty]s. [spawn] may throw synchronously when the shell cannot be
/// started; the session manager reports that as `spawn_failed`.
abstract interface class PtyFactory {
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  });
}
