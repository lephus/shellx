import 'package:flutter/services.dart';

/// macOS: opening ShellX again (Finder, Spotlight, Launchpad) while it runs
/// does not start a second process, so the single-instance signal never
/// fires: LaunchServices sends the running app a reopen event instead.
/// `AppDelegate.applicationShouldHandleReopen` forwards it here as a
/// `reopen` call.
const MethodChannel appReopenChannel = MethodChannel('pro.shellx.desktop/app');

/// Calls [onReopen] for every reopen of the running app (macOS).
void listenForReopen(
  void Function() onReopen, {
  MethodChannel channel = appReopenChannel,
}) {
  channel.setMethodCallHandler((call) async {
    if (call.method == 'reopen') onReopen();
  });
}
