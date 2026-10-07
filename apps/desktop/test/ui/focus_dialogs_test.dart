import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/clipboard_media.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/terminal/ssh_connect_dialog.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

/// A10 D23 F2 for the dialogs, which only the whole app (not the bare
/// workspace page) hosts. Same setup as `ssh_connect_route_test.dart`.
late ProviderContainer container;

String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> pumpApp(WidgetTester tester) async {
  final h = TestHarness(settings: {'onboarding_done': true});
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(FakeLocalSessions()),
      clipboardMediaProvider.overrideWithValue(const EmptyClipboardMedia()),
      ...configOverrides(MemoryConfigFs()),
    ],
  );
  await h.seedSignedIn();
  await container
      .read(agentControllerProvider.notifier)
      .bootstrap(watchForWake: false);
  await loadConfig(container);
  container.read(windowRouterProvider.notifier).showTerminal();
  tester.view.physicalSize = const Size(1100, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ShellxDesktopApp(locale: Locale('en')),
    ),
  );
  await container.read(terminalTabsProvider.notifier).openTab();
  await tester.pumpAndSettle();
}

void testApp(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      description,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        await pumpApp(tester);
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
        }
      },
    );

void main() {
  testApp('F2: the connect dialog closing gives the keyboard back', (
    tester,
  ) async {
    expect(focusLabel(), 'terminal');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(SshConnectDialog), findsOneWidget);
    expect(focusLabel(), isNot('terminal'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SshConnectDialog), findsNothing);
    expect(focusLabel(), 'terminal');
  });

  testApp('F2: a confirmation answered gives the keyboard back', (
    tester,
  ) async {
    final ask = container
        .read(windowRouterProvider.notifier)
        .confirm(
          ConfirmRequest(title: 'Sure?', body: 'Body', confirmLabel: 'Yes'),
        );
    await tester.pumpAndSettle();
    expect(find.text('Sure?'), findsOneWidget);
    expect(focusLabel(), isNot('terminal'));
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(await ask, isTrue);
    expect(focusLabel(), 'terminal');
  });

  pasteConfirmTests();

  testApp('F2: a confirmation cancelled with Esc gives the keyboard back', (
    tester,
  ) async {
    final ask = container
        .read(windowRouterProvider.notifier)
        .confirm(
          ConfirmRequest(title: 'Sure?', body: 'Body', confirmLabel: 'Yes'),
        );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await ask, isFalse);
    expect(focusLabel(), 'terminal');
  });
}

extension on WidgetTester {
  void mockClipboardText(String text) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': text} : null,
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }
}

void pasteConfirmTests() {
  testApp('F2: the paste confirmation answered gives the keyboard back', (
    tester,
  ) async {
    tester.mockClipboardText('y' * (1024 * 1024 + 10));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Paste 1.0 MB'), findsOneWidget);
    expect(focusLabel(), isNot('terminal'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focusLabel(), 'terminal');
  });
}
