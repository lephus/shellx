import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/dialogs/route_dialog.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/terminal/ssh_connect_dialog.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

late ProviderContainer container;

/// The whole window (the dialog host is the app's), signed in, one tab.
Future<void> pumpApp(WidgetTester tester) async {
  final h = TestHarness(settings: {'onboarding_done': true});
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(FakeLocalSessions()),
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

/// Bootstrap starts timers: the tree goes before the test ends.
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

const cmd = LogicalKeyboardKey.metaLeft;
const shift = LogicalKeyboardKey.shiftLeft;

Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(cmd);
  await tester.sendKeyDownEvent(shift);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(shift);
  await tester.sendKeyUpEvent(cmd);
  await tester.pumpAndSettle();
}

void main() {
  test('the route has a width of its own and a tab', () {
    expect(
      dialogWidthFor(const WindowState(route: SshConnectRoute())),
      ShellxSizes.connectDialogWidth,
    );
    expect(const SshConnectRoute().tab, SshDialogTab.ssh);
    expect(const SshConnectRoute(SshDialogTab.tmux).tab, SshDialogTab.tmux);
  });

  testApp('⌘⇧K opens the dialog, Esc closes it', (tester) async {
    await chord(tester, LogicalKeyboardKey.keyK);
    expect(find.byType(SshConnectDialog), findsOneWidget);
    expect(find.text('Connect to a server'), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ssh.host')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SshConnectDialog), findsNothing);
  });

  testApp('⌘⇧K does nothing while another dialog is open', (tester) async {
    container.read(windowRouterProvider.notifier).open(const PairingRoute());
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyK);
    expect(container.read(windowRouterProvider).route, isA<PairingRoute>());
    expect(find.byType(SshConnectDialog), findsNothing);
  });

  testApp('the palette lists "Attach tmux session"; it opens the tmux tab', (
    tester,
  ) async {
    await chord(tester, LogicalKeyboardKey.keyP);
    await tester.enterText(find.byType(TextField), 'tmux');
    await tester.pumpAndSettle();
    expect(find.text('Attach tmux session'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SshConnectDialog), findsOneWidget);
    expect(find.byKey(const Key('tmux.source')), findsOneWidget);
  });

  testApp('right-click on + offers New tab / Connect / Attach', (tester) async {
    await tester.tap(
      find.byKey(const Key('sidebar.newTab')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.new.tab')), findsOneWidget);
    expect(find.text('Connect over SSH…'), findsOneWidget);
    expect(find.text('⌘⇧K'), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu.new.tmux')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tmux.source')), findsOneWidget);
  });

  testApp('Shift+F10 on the focused + opens the same menu', (tester) async {
    // The button's own focus node: the nearest one above its inner parts.
    final inner = find
        .descendant(
          of: find.byKey(const Key('sidebar.newTab')),
          matching: find.byType(SizedBox),
        )
        .first;
    final node = Focus.of(tester.element(inner));
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.new.ssh')), findsOneWidget);
  });

  bool terminalHasFocus(WidgetTester tester) => tester
      .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage))
      .terminalFocus
      .hasFocus;

  testApp('after Cancel / Esc and after Connect the terminal has the '
      'keyboard (UI §3.6)', (tester) async {
    await chord(tester, LogicalKeyboardKey.keyK);
    expect(terminalHasFocus(tester), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(terminalHasFocus(tester), isTrue);
    await chord(tester, LogicalKeyboardKey.keyK);
    await tester.enterText(find.byKey(const Key('ssh.host')), 'devbox');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(SshConnectDialog), findsNothing);
    expect(terminalHasFocus(tester), isTrue);
  });

  testApp('the shortcut sheet and the palette list both actions', (
    tester,
  ) async {
    container
        .read(configUiRequestProvider.notifier)
        .request(ConfigUiRequest.shortcuts);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('shortcuts.row.ssh_connect')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('shortcuts.row.tmux_attach')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyP);
    await tester.enterText(find.byType(TextField), 'ssh');
    await tester.pumpAndSettle();
    expect(find.text('Connect over SSH'), findsOneWidget);
  });
}
