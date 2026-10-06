import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

void main() {
  test('active = focused and visible (D25)', () {
    final c = ProviderContainer.test();
    expect(c.read(windowActiveProvider), isFalse);
    c.read(windowFocusProvider.notifier).set(true);
    expect(c.read(windowActiveProvider), isFalse); // hidden
    c.read(windowRouterProvider.notifier).showTerminal();
    expect(c.read(windowActiveProvider), isTrue);
    c.read(windowRouterProvider.notifier).hideWindow();
    expect(c.read(windowActiveProvider), isFalse);
  });

  test('readWindowActive reads the sources at the call (D25)', () {
    final c = ProviderContainer.test();
    final probe = Provider<Ref>((ref) => ref);
    final ref = c.read(probe);
    expect(readWindowActive(ref), isFalse);
    c.read(windowFocusProvider.notifier).set(true);
    c.read(windowRouterProvider.notifier).showTerminal();
    expect(readWindowActive(ref), isTrue);
    c.read(windowRouterProvider.notifier).hideWindow();
    expect(readWindowActive(ref), isFalse);
  });

  test('focus requests count up', () {
    final c = ProviderContainer.test();
    c.read(terminalFocusRequestProvider.notifier).request();
    c.read(terminalFocusRequestProvider.notifier).request();
    expect(c.read(terminalFocusRequestProvider), 2);
  });
}
