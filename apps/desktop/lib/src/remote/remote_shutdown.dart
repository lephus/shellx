import 'package:shellx_agent/shellx_agent.dart';

import '../startup.dart';

/// A8 D40, the real shutdown (tray Quit, after the sessions close): the
/// remote port watcher stops, every forward process is killed and every
/// ssh master ShellX started is told to exit. Bounded, never throws.
Future<void> shutdownRemote(
  RemoteTools tools, {
  required void Function() disposeWatcher,
}) async {
  try {
    disposeWatcher();
  } catch (_) {}
  final control = tools.control;
  if (control == null) return;
  await runBounded(
    () => control.exitMasters(control.mastersUsed.toList()),
    timeout: const Duration(seconds: 3),
    label: 'closing ssh connections',
  );
}
