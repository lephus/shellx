import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key marking that this install already ran once.
const String installMarkerKey = 'shellx_installed';

/// iOS keeps Keychain items after the app is deleted. Spec §5.1 says a
/// reinstall generates a new device key (and must be paired again), so the
/// first launch of a fresh install wipes secure storage. The marker lives in
/// SharedPreferences, which the OS deletes together with the app.
///
/// A wipe that fails never blocks the launch: the marker is then left unset, so the next launch
/// wipes again.
Future<void> wipeSecureStorageOnFreshInstall({
  required SharedPreferences prefs,
  required Future<void> Function() wipe,
}) async {
  if (prefs.getBool(installMarkerKey) ?? false) return;
  try {
    await wipe();
  } catch (error) {
    if (kDebugMode) debugPrint('Fresh-install wipe error: ${error.runtimeType}');
    return;
  }
  await prefs.setBool(installMarkerKey, true);
}
