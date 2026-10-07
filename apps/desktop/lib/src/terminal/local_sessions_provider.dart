import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../l10n/app_localizations.dart';
import '../agent/desktop_services.dart';
import '../mux/daemon_state.dart';

/// The window's only way into the sessions (A1 spec §3.1).
///
/// A5b: a window attached to the background service gets the connection's
/// sessions (and, until it is attached, none).
final localSessionsProvider = Provider<LocalSessions>((ref) {
  if (ref.watch(daemonModeProvider)) {
    return ref.watch(daemonLinkProvider)?.sessions ??
        const UnattachedSessions();
  }
  return ref.watch(desktopServicesProvider).sessions;
});

/// The window before it is attached to the background service: nothing
/// runs, nothing opens.
final class UnattachedSessions implements LocalSessions {
  const UnattachedSessions();
  @override
  List<SessionSummary> get sessions => const [];
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Stream<SessionNotice> get notices => const Stream.empty();
  @override
  Future<int> open({
    required int cols,
    required int rows,
    String? cwd,
    int? tabId,
    SessionLaunch? launch,
  }) => Future.error(const SpawnFailedException('daemon_unavailable'));
  @override
  bool notify(int id, {String? title, required String body}) => false;
  @override
  LocalSessionView view(int id) => throw StateError('no session $id');
  @override
  void close(int id) {}
  @override
  void watchPorts(bool visible) {}
}

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
