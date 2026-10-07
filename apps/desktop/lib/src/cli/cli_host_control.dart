import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ruling M6: lets Quit stop the host first, before the sessions close.
final cliHostControlProvider = Provider<CliHostControl>(
  (_) => CliHostControl(),
);

/// What the process that runs the CLI host hands to the rest of the app.
final class CliHostControl {
  /// Set by a running [CliService].
  Future<void> Function()? stop;

  /// `CliHost.recheck`: the agent calls it right after it changed a CLI
  /// switch (A5b D13), so open connections follow at once. Set by a
  /// running service; the agent runs in the same process as the host.
  void Function()? recheck;

  /// Stops the host once; nothing when none runs.
  Future<void> stopNow() async {
    final s = stop;
    stop = null;
    recheck = null;
    await s?.call();
  }
}
