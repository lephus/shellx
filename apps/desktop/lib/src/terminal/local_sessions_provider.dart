import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../l10n/app_localizations.dart';
import '../agent/desktop_services.dart';

/// The window's only way into the sessions (A1 spec §3.1).
final localSessionsProvider = Provider<LocalSessions>(
  (ref) => ref.watch(desktopServicesProvider).sessions,
);

/// Strings for code that has no BuildContext (the exit line).
final appL10nProvider = Provider<AppLocalizations>(
  (ref) => ref.watch(desktopServicesProvider).l10n,
);

/// The user's home, for showing `~` (UI-A2 §2.3). `main.dart` overrides
/// it with the home the shells start in.
final homeDirectoryProvider = Provider<String>(
  (ref) =>
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '',
);
