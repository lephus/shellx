import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/window_coordinator.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';

/// Contract §5 (force update): below `min_agent` every window shows only
/// "Update required" — download or quit — until a later check lifts it.
void main() {
  late TestHarness h;
  late ProviderContainer container;

  AgentControllerBase agent() =>
      container.read(agentControllerProvider.notifier);
  WindowRouter router() => container.read(windowRouterProvider.notifier);

  /// This build is 0.9.0; the relay's `min_agent` and latest are 1.0.0.
  Future<void> pump(WidgetTester tester) async {
    h = TestHarness(appVersion: '0.9.0', settings: {'onboarding_done': true});
    container = ProviderContainer(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    await agent().bootstrap(watchForWake: false);
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ShellxDesktopApp(locale: Locale('en')),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Tears the app down inside the body (bootstrap starts the periodic
  /// update check: no timer may be left pending).
  void testApp(String description, Future<void> Function(WidgetTester) body) =>
      testWidgets(description, (tester) async {
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
        }
      });

  final page = find.byKey(const Key('updateRequired'));
  final workspace = find.byKey(const Key('sidebar.newTab'));

  testApp('replaces the terminal window: title, both versions, and the '
      'download opens the trusted link', (tester) async {
    await pump(tester);
    expect(page, findsOneWidget);
    expect(workspace, findsNothing);
    expect(find.text('Update required'), findsOneWidget);
    expect(
      find.text(h.l10n.updateRequiredBody('0.9.0', '1.0.0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('updateRequired.download')));
    await tester.pump();
    expect(
      h.urlOpener.opened.single.toString(),
      'https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg',
    );
  });

  testApp('a route (sign in, pairing…) waits behind it; keys never reach '
      'the shell', (tester) async {
    await pump(tester);
    await h.sessions.open(cols: 80, rows: 24);
    router().open(const LoginRoute());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dialog')), findsNothing);
    expect(page, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(h.ptys.ptys.single.writtenText, isEmpty);
  });

  testApp('Quit takes the usual way out, with its question over the page '
      'when a shell runs', (tester) async {
    await pump(tester);
    await h.sessions.open(cols: 80, rows: 24);
    await tester.pump();

    await tester.tap(find.byKey(const Key('updateRequired.quit')));
    await tester.pumpAndSettle();
    expect(find.text(h.l10n.confirmQuitTitle), findsOneWidget);
    expect(h.quits, 0);

    await tester.tap(find.byKey(const Key('confirm.ok')));
    await tester.pumpAndSettle();
    expect(h.quits, 1);
    expect(h.ptys.ptys.single.killed, isTrue);
  });

  testApp('a later check that lifts it brings the window back, with the '
      'route that waited', (tester) async {
    await pump(tester);
    router().open(const LoginRoute());
    await tester.pumpAndSettle();

    h.relay.version = {...h.relay.version, 'min_agent': '0.9.0'};
    await tester.runAsync(agent().checkForUpdate);
    await tester.pumpAndSettle();

    expect(page, findsNothing);
    expect(workspace, findsOneWidget);
    expect(find.byKey(const Key('dialog')), findsOneWidget);
  });

  test('the window shows when the block starts', () async {
    h = TestHarness();
    container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    container.listen(
      agentControllerProvider,
      (prev, next) => coordinateWindows(prev, next, router()),
    );
    await agent().bootstrap(watchForWake: false);
    await pumpEventQueue();
    expect(container.read(windowRouterProvider).visible, isFalse);

    h.relay.version = {...h.relay.version, 'min_agent': '1.1.0'};
    await agent().checkForUpdate();
    expect(container.read(windowRouterProvider).visible, isTrue);
  });
}
