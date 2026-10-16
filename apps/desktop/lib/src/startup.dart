import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

/// Runs the app's startup ([start]). Should anything in it throw, the process
/// must not live on invisibly, holding the single-instance lock so that
/// every later launch exits silently. So, on a throw:
/// 1. log the error's type only (never its message: it may hold secrets);
/// 2. [releaseLock] — before the error is shown, because a Windows
///    `MessageBox` blocks until dismissed and a relaunch meanwhile must work;
/// 3. [showError] to the user;
/// 4. [exit] with code 1.
///
/// Steps 2 and 3 are bounded by [stepTimeout] and never stop step 4.
Future<void> runGuardedStartup({
  required Future<void> Function() start,
  required Future<void> Function() releaseLock,
  required Future<void> Function() showError,
  required Never Function(int code) exit,
  void Function(String message)? log,
  Duration stepTimeout = const Duration(seconds: 5),
}) async {
  log ??= _debugLog;
  try {
    await start();
  } catch (error) {
    log('ShellX: startup failed: ${error.runtimeType}');
    await runBounded(
      releaseLock,
      timeout: stepTimeout,
      label: 'releasing the lock',
      log: log,
    );
    await runBounded(
      showError,
      timeout: stepTimeout,
      label: 'showing the startup error',
      log: log,
    );
    exit(1);
  }
}

/// Best effort with a deadline: runs [step], waits at most [timeout], never
/// throws. A failure is logged by type only, prefixed with [label].
Future<void> runBounded(
  Future<void> Function() step, {
  required Duration timeout,
  required String label,
  void Function(String message)? log,
}) async {
  try {
    await step().timeout(timeout);
  } catch (error) {
    (log ?? _debugLog)('ShellX: $label failed: ${error.runtimeType}');
  }
}

void _debugLog(String message) => debugPrint(message);
