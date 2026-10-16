import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/port_watch.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';

void main() {
  test('watchPorts follows whether the window is shown (A2 D8)', () {
    final local = FakeLocalSessions();
    final container = ProviderContainer.test();
    listenForPortWatch(container: container, sessions: local);
    expect(local.watched, [false]);
    container.read(windowRouterProvider.notifier).showTerminal();
    container.read(windowRouterProvider.notifier).showTerminal();
    expect(local.watched, [false, true]);
    container.read(windowRouterProvider.notifier).hideWindow();
    expect(local.watched, [false, true, false]);
  });
}
