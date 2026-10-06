import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../ui/window_router.dart';

/// A2 D8: listening ports are looked up only while the window is shown
/// (a dialog over it counts). Called once from `main.dart`.
void listenForPortWatch({
  required ProviderContainer container,
  required LocalSessions sessions,
}) {
  container.listen<bool>(
    windowRouterProvider.select((s) => s.visible),
    (_, shown) => sessions.watchPorts(shown),
    fireImmediately: true,
  );
}
