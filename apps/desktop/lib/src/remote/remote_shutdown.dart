import 'package:shellx_agent/shellx_agent.dart';

/// A8 D40, the real shutdown (tray Quit, after the sessions close): the
/// remote port watcher stops, every forward process is killed and every
/// ssh master ShellX started is told to exit. The caller bounds it (the
/// tray's `runBounded`) and logs a failure by type.
Future<void> shutdownRemote(
  RemoteTools tools, {
  required void Function() disposeWatcher,
}) async {
  try {
    disposeWatcher();
  } catch (_) {}
  final control = tools.control;
  if (control == null) return;
  await control.exitMasters(control.mastersUsed.toList());
}
