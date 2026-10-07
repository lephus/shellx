import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What a finished helper command printed (`ssh -G`, `ssh -O`, probes,
/// `tmux list-sessions`). Never logged (A8 D37).
final class CommandResult {
  const CommandResult(
    this.exitCode,
    this.stdout,
    this.stderr, {
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Killed after its timeout ([exitCode] is −1).
  final bool timedOut;

  @override
  String toString() => 'CommandResult($exitCode, timedOut: $timedOut)';
}

typedef CommandRunner =
    Future<CommandResult> Function(
      String executable,
      List<String> arguments, {
      Duration timeout,
    });

/// A8 security ruling: helpers run on this computer must never see the
/// ShellX control-socket credentials, which only the shells' own map holds.
const List<String> _privateVariables = ['SHELLX_CLI_TOKEN', 'SHELLX_SOCKET'];

/// [base] without the ShellX control-socket variables.
Map<String, String> helperEnvironment(Map<String, String> base) => {
  for (final entry in base.entries)
    if (!_privateVariables.contains(entry.key.toUpperCase()))
      entry.key: entry.value,
};

const int _maxOutput = 1024 * 1024;

/// Runs a helper without a shell; kills it once [timeout] passes. A
/// missing executable is exit 127, as a shell reports it. Stdin is closed
/// at once (ssh then sends EOF to the remote command). [parentEnvironment]
/// stands in for the app's environment (tests).
Future<CommandResult> runCommand(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 5),
  Map<String, String>? parentEnvironment,
}) async {
  final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      environment: helperEnvironment(parentEnvironment ?? Platform.environment),
      includeParentEnvironment: false,
    );
  } on ProcessException {
    return const CommandResult(127, '', '');
  }
  unawaited(process.stdin.close().catchError((Object _) {}));
  final out = _collect(process.stdout);
  final err = _collect(process.stderr);
  var timedOut = false;
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      process.kill();
      return -1;
    },
  );
  const grace = Duration(seconds: 1);
  return CommandResult(
    code,
    await out.timeout(grace, onTimeout: () => ''),
    await err.timeout(grace, onTimeout: () => ''),
    timedOut: timedOut,
  );
}

Future<String> _collect(Stream<List<int>> stream) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (bytes.length < _maxOutput) bytes.add(chunk);
  }
  return const Utf8Decoder(allowMalformed: true).convert(bytes.takeBytes());
}
