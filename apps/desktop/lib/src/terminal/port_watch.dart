import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../ui/window_router.dart';
import 'local_sessions_provider.dart';

/// A2 D8: listening ports are looked up only while the window is shown
/// (a dialog over it counts). Called once from `main.dart`.
///
/// Without [sessions] the window's current sessions are used, and the
/// choice is sent again whenever they change (a new connection to the
/// background service, A5b).
void listenForPortWatch({
  required ProviderContainer container,
  LocalSessions? sessions,
}) {
  LocalSessions current() => sessions ?? container.read(localSessionsProvider);
  container.listen<bool>(
    windowRouterProvider.select((s) => s.visible),
    (_, shown) => current().watchPorts(shown),
    fireImmediately: true,
  );
  if (sessions == null) {
    container.listen<LocalSessions>(
      localSessionsProvider,
      (_, next) =>
          next.watchPorts(container.read(windowRouterProvider).visible),
    );
  }
}
