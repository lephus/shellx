import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/settings_store.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import 'desktop_services.dart';
import 'whats_new.dart';

/// The bundled release notes (`pubspec.yaml` assets): no network.
const String kWhatsNewAsset = 'assets/whats_new.json';

/// Where the notes come from; a test swaps it.
final whatsNewSourceProvider = Provider<Future<String> Function()>(
  (ref) =>
      () => rootBundle.loadString(kWhatsNewAsset),
);

/// The bundled notes; a missing or damaged asset is "no notes".
final whatsNewProvider = FutureProvider<WhatsNew>((ref) async {
  try {
    return WhatsNew.parse(await ref.read(whatsNewSourceProvider)());
  } catch (_) {
    return WhatsNew.empty;
  }
});

/// The running version (from `PackageInfo`, read at startup into
/// [DesktopServices]); null where there are no services (nothing is shown).
final currentVersionProvider = Provider<String?>((ref) {
  try {
    return ref.watch(desktopServicesProvider).appVersion;
  } catch (_) {
    return null;
  }
});

final tourStateProvider = Provider<TourState>(
  (ref) => TourState(ref.watch(settingsStoreProvider)),
);

/// What the window shows once after it opens (A11 D23, D24).
enum FirstRunStep { tour, whatsNew, none }

/// The rule: a fresh install gets the tour; someone who has used the app
/// before A11 (no [lastSeen] and no [tourDone], but [existingUser]) is an
/// upgrade, never a first run; a newer release than [lastSeen] gets "what is
/// new" when it has notes. Releases are compared without the build number.
FirstRunStep decideFirstRun({
  required bool tourDone,
  required String? lastSeen,
  required String current,
  required bool hasNotesFor,
  bool existingUser = false,
}) {
  final seen = lastSeen == null ? null : releaseOf(lastSeen);
  if (seen != null) {
    if (seen == releaseOf(current)) return FirstRunStep.none;
    return hasNotesFor ? FirstRunStep.whatsNew : FirstRunStep.none;
  }
  if (tourDone) return FirstRunStep.none;
  if (existingUser) {
    return hasNotesFor ? FirstRunStep.whatsNew : FirstRunStep.none;
  }
  return FirstRunStep.tour;
}

/// True when this install has run before A11 (or without ever recording a
/// version): a trace only the UI process writes. Read once, before the
/// window writes anything of its own.
bool hasUsedAppBefore(SettingsStore store) =>
    store.getStrings(SettingKeys.terminalWorkspaces).isNotEmpty ||
    store.getInt(SettingKeys.windowWidth) != null;

/// The two UI-owned flags (not sensitive). A failed write is only logged by
/// kind: the tour is a courtesy.
final class TourState {
  const TourState(this._store);
  final SettingsStore _store;

  bool get tourDone =>
      _store.getBool(SettingKeys.tourDone, defaultValue: false);

  String? get lastSeenVersion {
    final v = _store.getStrings(SettingKeys.lastSeenVersion);
    return v.isEmpty ? null : releaseOf(v.first);
  }

  Future<void> markTourDone() =>
      _guard(() => _store.setBool(SettingKeys.tourDone, true));

  Future<void> setLastSeenVersion(String version) => _guard(
    () => _store.setStrings(SettingKeys.lastSeenVersion, [releaseOf(version)]),
  );

  Future<void> _guard(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      debugPrint('tour state: write failed (${e.runtimeType})');
    }
  }
}
