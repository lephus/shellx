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
  } on Object {
    return const CommandResult(127, '', '');
  }
  unawaited(process.stdin.close().catchError((Object _) {}));
  final out = _Capture(process.stdout);
  final err = _Capture(process.stderr);
  var timedOut = false;
  var code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      // Windows has no SIGKILL; TerminateProcess is what kill() does there.
      process.kill(
        Platform.isWindows ? ProcessSignal.sigterm : ProcessSignal.sigkill,
      );
      return -1;
    },
  );
  if (timedOut) {
    code = -1;
  }
  const grace = Duration(seconds: 1);
  return CommandResult(
    code,
    await out.text(grace),
    await err.text(grace),
    timedOut: timedOut,
  );
}

/// A stream's text so far; errors and an endless stream never escape.
final class _Capture {
  _Capture(Stream<List<int>> stream) {
    _subscription = stream.listen(
      (chunk) {
        if (_bytes.length < _maxOutput) _bytes.add(chunk);
      },
      onError: (Object _) {},
      onDone: _done.complete,
      cancelOnError: false,
    );
  }

  final _bytes = BytesBuilder(copy: false);
  final _done = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;

  /// Waits up to [grace] for the stream to end, then keeps what arrived.
  Future<String> text(Duration grace) async {
    await _done.future.timeout(grace, onTimeout: () {});
    unawaited(_subscription.cancel().catchError((Object _) {}));
    return const Utf8Decoder(allowMalformed: true).convert(_bytes.takeBytes());
  }
}
