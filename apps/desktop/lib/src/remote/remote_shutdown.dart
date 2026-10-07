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
  // A5b R2: a UI-side SshControl shares the directory, not `mastersUsed`:
  // every master socket in it ends, the ones this instance never noted too.
  await control.exitAllMasters();
}

/// A5b "Thoát" (the window only): this window's own port forwards end; no
/// master is told to exit, because the shells of the background service
/// still use them ("Thoát hoàn toàn" ends them in the service). The caller
/// bounds it.
Future<void> cancelUiForwards(RemoteTools tools) async {
  final control = tools.control;
  if (control == null) return;
  for (final target in control.mastersUsed.toList()) {
    try {
      await control.cancelForwards(target);
    } on Object {
      // The forward is gone or ssh is: nothing more to cancel.
    }
  }
}
