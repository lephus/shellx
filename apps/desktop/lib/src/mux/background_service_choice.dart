import 'package:shellx_agent/shellx_agent.dart';

import 'daemon_launcher.dart';

/// Whether this launch attaches to the background service (A5b D13 ruling).
///
/// With the switch [enabled]: yes (the launcher connects or starts one).
/// With it off the app runs its shells itself, exactly as before A5b — unless
/// a service still runs from when the switch was on (R3: never two hosts):
/// one with no sessions is quit and the app runs in-process; one that holds
/// sessions (or whose count is unknown) is never stopped unasked, so this
/// launch attaches to it and "Thoát hoàn toàn" ends it.
///
/// [findRunning] never starts or replaces a service; [quit] asks the found
/// one to exit and closes the link.
Future<bool> attachThisLaunch({
  required bool enabled,
  required Future<bool> Function() daemonLockFree,
  required Future<DaemonConnection?> Function() findRunning,
  required Future<void> Function(MuxClient client) quit,
}) async {
  if (enabled) return true;
  // No service ever started (nothing holds `mux.lock`): nothing to probe.
  if (await daemonLockFree()) return false;
  final found = await findRunning();
  final (client, sessions) = switch (found) {
    Attached(:final client, :final info) => (client, info.sessions),
    Incompatible(:final client, :final info) => (client, info.sessions),
    _ => (null, null),
  };
  if (client == null) return false;
  if (sessions == 0) {
    await quit(client);
    return false;
  }
  // The probe's link is not the window's: the launcher connects again.
  try {
    await client.close();
  } on Object {
    // Already closed.
  }
  return true;
}
