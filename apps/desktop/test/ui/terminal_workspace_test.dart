import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

late TestHarness h;
late FakeLocalSessions local;
late ProviderContainer container;

Future<void> pumpWorkspace(WidgetTester tester, {bool signedIn = true}) async {
  h = TestHarness(settings: {'onboarding_done': true});
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
    ],
  );
  if (signedIn) await h.seedSignedIn();
  await container
      .read(agentControllerProvider.notifier)
      .bootstrap(watchForWake: false);
  tester.view.physicalSize = const Size(1100, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: TerminalWorkspacePage()),
      ),
    ),
  );
  await tester.pump();
}

TerminalTabsState tabs() => container.read(terminalTabsProvider);

/// [testWidgets] that tears the workspace down inside the body: bootstrap
/// starts the periodic update check, and testWidgets fails on pending
/// timers before any addTearDown callback could dispose the container.
void testWorkspace(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  TestVariant<Object?> variant = const DefaultTestVariant(),
}) => testWidgets(description, variant: variant, (tester) async {
  try {
    await body(tester);
  } finally {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }
});

/// The primary focus sits inside [finder] (UI §3.6 focus checks).
bool focusIn(Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return find
      .descendant(
        of: finder,
        matching: find.byElementPredicate(
          (e) => identical(e, focused),
          skipOffstage: false,
        ),
        skipOffstage: false,
      )
      .evaluate()
      .isNotEmpty;
}

void main() {
  setUp(() => local = FakeLocalSessions());

  testWorkspace('sidebar lists tabs with title, origin and viewing marks', (
    tester,
  ) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    local.add(local.summary(2, title: 'claude', attachedMobileId: 'm1'));
    await pumpWorkspace(tester);

    expect(
      find.text('zsh 1'),
      findsOneWidget,
    ); // the row (no pane header off macOS)
    expect(find.text('claude'), findsOneWidget);
    final phoneRow = find.byKey(const ValueKey('tab.2'));
    expect(
      find.descendant(
        of: phoneRow,
        matching: find.byIcon(Icons.smartphone_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: phoneRow,
        matching: find.byIcon(Icons.visibility_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tab.1')),
        matching: find.byIcon(Icons.smartphone_outlined),
      ),
      findsNothing,
    );
    expect(tester.getSize(find.byKey(const ValueKey('tab.1'))).height, 30);
  });

  testWorkspace('clicking a row selects it and shows its terminal', (
    tester,
  ) async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    await pumpWorkspace(tester);
    await tester.tap(find.byKey(const ValueKey('tab.2')));
    await tester.pump();
    expect(tabs().selectedId, 2);
  });

  testWorkspace('+ opens a tab at the measured grid', (tester) async {
    await pumpWorkspace(tester);
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    expect(local.opens, hasLength(1));
    // The pane is 1100 − 220 (sidebar) − 1 (divider) wide and the full
    // 720 high (no macOS pane header in tests, signed in: no strip). The
    // test font draws square glyphs, so compare with the measured grid
    // rather than with real JetBrains Mono column counts.
    final grid = measureTerminalGrid(
      ShellxSizes.terminalPadding.deflateSize(const Size(879, 720)),
      desktopTerminalStyle(kTerminalFontSizeDefault),
      TextScaler.noScaling,
    )!;
    expect(local.opens.single, (grid.cols, grid.rows));
    expect(local.opens.single, isNot((80, 24))); // not the fallback grid
  });

  testWorkspace('the driver pill shows only while the phone drives', (
    tester,
  ) async {
    local.add(local.summary(1, attachedMobileId: 'm1'));
    await pumpWorkspace(tester);
    expect(find.byKey(const Key('pane.driverPill')), findsOneWidget);
    expect(
      find.text('Your phone is using this terminal — type to take it back'),
      findsOneWidget,
    );
    local.views[1]!.driverController.add(DriverSide.desktop);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.driverPill')), findsNothing);
  });

  testWorkspace('signed out: the strip shows and opens the login dialog', (
    tester,
  ) async {
    await pumpWorkspace(tester, signedIn: false);
    expect(find.byKey(const Key('pane.signedOutStrip')), findsOneWidget);
    expect(
      find.text('Sign in to use this computer from your phone'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('pane.signIn')));
    expect(container.read(windowRouterProvider).route, isA<LoginRoute>());
  });

  testWorkspace('signed in: no strip', (tester) async {
    await pumpWorkspace(tester);
    expect(find.byKey(const Key('pane.signedOutStrip')), findsNothing);
  });

  testWorkspace('no tabs: the empty state opens a tab', (tester) async {
    await pumpWorkspace(tester);
    expect(find.byKey(const Key('pane.empty')), findsOneWidget);
    expect(find.text('No tabs open'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pane.empty.open')));
    await tester.pump();
    expect(local.opens, hasLength(1));
  });

  testWorkspace('the session limit shows a toast that can be dismissed', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    local.openError = const SessionLimitException(32);
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.text(
        "You've reached the limit of 32 sessions. Close a tab to open a new one.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('pane.toast.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.toast')), findsNothing);
  });

  testWorkspace('the toast goes away on its own after 6 s', (tester) async {
    await pumpWorkspace(tester);
    local.openError = const SpawnFailedException('No such file or directory');
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    expect(find.textContaining('shell not found'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.toast')), findsNothing);
  });

  testWorkspace('context menu "Close tab" closes an idle tab at once', (
    tester,
  ) async {
    local.add(local.summary(1));
    await pumpWorkspace(tester);
    await tester.tap(
      find.byKey(const ValueKey('tab.1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.closeTab')));
    await tester.pumpAndSettle();
    expect(local.closed, [1]);
  });

  testWorkspace('closing a tab with a running command asks first (D15)', (
    tester,
  ) async {
    local.add(local.summary(1, title: 'claude', runningCommand: true));
    await pumpWorkspace(tester);
    await tester.tap(
      find.byKey(const ValueKey('tab.1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.closeTab')));
    await tester.pump();
    final confirm = container.read(windowRouterProvider).confirm!;
    expect(confirm.title, 'Close “claude”?');
    confirm.complete(false);
    await tester.pump();
    expect(local.closed, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('tab.1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.closeTab')));
    await tester.pump();
    container.read(windowRouterProvider).confirm!.complete(true);
    await tester.pump();
    expect(local.closed, [1]);
  });

  testWorkspace('a middle click closes the tab', (tester) async {
    local.add(local.summary(1));
    await pumpWorkspace(tester);
    final center = tester.getCenter(find.byKey(const ValueKey('tab.1')));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.up();
    await tester.pump();
    expect(local.closed, [1]);
  });

  testWorkspace('rows announce status, origin and position (UI §3.7)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    local.add(local.summary(1, title: 'claude', runningCommand: true));
    local.add(local.summary(2, attachedMobileId: 'm1'));
    await pumpWorkspace(tester);
    expect(
      find.bySemanticsLabel(
        'claude, running a command, opened from your phone, tab 1 of 2',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'zsh 2, idle, opened from your phone, your phone is using it, '
        'tab 2 of 2',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWorkspace('every tab stays mounted so hidden tabs keep their terminal', (
    tester,
  ) async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    await pumpWorkspace(tester);
    expect(find.byKey(const ValueKey('terminal.1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('terminal.2'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWorkspace('a non-zero exit shows the hollow dot and is announced '
      '(UI §2.6)', (tester) async {
    final semantics = tester.ensureSemantics();
    local.add(local.summary(1));
    await pumpWorkspace(tester);
    local.views[1]!.end(2);
    await tester.pump();
    await tester.pump(); // the exit code arrives after the first frame
    expect(
      find.bySemanticsLabel(
        'zsh 1, exited with code 2, opened from your phone, tab 1 of 1',
      ),
      findsOneWidget,
    );
    final title = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('tab.1')),
        matching: find.text('zsh 1'),
      ),
    );
    expect(title.style!.color, ShellxDesktopColors.textSecondary);
    semantics.dispose();
  });

  testWorkspace('the eye mark is yellow while the phone drives, cyan while '
      'it only views (UI §3.1)', (tester) async {
    local.add(local.summary(1, attachedMobileId: 'm1'));
    local.add(
      local.summary(2, attachedMobileId: 'm1', driver: DriverSide.desktop),
    );
    await pumpWorkspace(tester);
    Color eye(int id) => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(ValueKey('tab.$id')),
            matching: find.byIcon(Icons.visibility_outlined),
          ),
        )
        .color!;
    expect(eye(1), ShellxDesktopColors.warn);
    expect(eye(2), ShellxDesktopColors.accent);
  });

  testWorkspace('the terminal has the keyboard first and follows the '
      'selection (UI §3.6)', (tester) async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    await pumpWorkspace(tester);
    final page = tester.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    bool focusIn(int id) =>
        page.terminalFocus.hasFocus &&
        find
            .descendant(
              of: find.byKey(ValueKey('terminal.$id'), skipOffstage: false),
              matching: find.byElementPredicate(
                (e) => identical(e, page.terminalFocus.context),
                skipOffstage: false,
              ),
              skipOffstage: false,
            )
            .evaluate()
            .isNotEmpty;
    expect(focusIn(1), isTrue);
    await tester.tap(find.byKey(const ValueKey('tab.2')));
    await tester.pump();
    await tester.pump();
    expect(focusIn(2), isTrue);
  });

  testWorkspace('Shift+F10 in the sidebar opens the row menu; Esc closes it', (
    tester,
  ) async {
    local.add(local.summary(1));
    await pumpWorkspace(tester);
    final page = tester.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    page.sidebarFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.closeTab')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.closeTab')), findsNothing);
    expect(local.closed, isEmpty);
  });

  testWorkspace('+ shows a spinner and ignores clicks while an open is in '
      'flight (UI §3.2)', (tester) async {
    await pumpWorkspace(tester);
    final gate = local.openGate = Completer<void>();
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    final spinner = find.descendant(
      of: find.byKey(const Key('sidebar.newTab')),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinner, findsOneWidget);
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    expect(local.opens, hasLength(1));
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(spinner, findsNothing);
    expect(tabs().tabs, hasLength(1));
  });

  testWorkspace('the toast waits while the pointer is over it (UI §2.8)', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    local.openError = const SessionLimitException(32);
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 10));
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('pane.toast'))));
    await tester.pump(const Duration(seconds: 7));
    // Let a dismissal (if any) finish its exit animation.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('pane.toast')), findsOneWidget);
    await mouse.moveTo(const Offset(400, 10));
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.toast')), findsNothing);
    await mouse.removePointer();
  });

  testWorkspace('macOS: 38 px header band with + on the traffic-light line, '
      'pane header with the title (UI §2.1)', (tester) async {
    local.add(local.summary(1, title: 'claude'));
    await pumpWorkspace(tester);
    expect(tester.getTopLeft(find.byKey(const ValueKey('tab.1'))).dy, 42);
    final plus = tester.getCenter(find.byKey(const Key('sidebar.newTab')));
    expect(plus.dy, 14);
    // 24 px visual centred in the 28 px hit box, 8 px from the right edge.
    expect(plus.dx + 12, 220 - 8);
    expect(find.text('claude'), findsNWidgets(2)); // row + pane header
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWorkspace(
    'Windows: 36 px header band, no pane header (UI §2.1)',
    (tester) async {
      local.add(local.summary(1, title: 'claude'));
      await pumpWorkspace(tester);
      expect(tester.getTopLeft(find.byKey(const ValueKey('tab.1'))).dy, 40);
      expect(tester.getCenter(find.byKey(const Key('sidebar.newTab'))).dy, 18);
      expect(find.text('claude'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWorkspace('the exited dot is a hollow red ring (UI §3.1)', (
    tester,
  ) async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    await pumpWorkspace(tester);
    local.views[1]!.end(2);
    await tester.pump();
    await tester.pump();
    BoxDecoration dot(int id) =>
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(ValueKey('tab.$id')),
                    matching: find.byWidgetPredicate(
                      (w) =>
                          w is Container &&
                          w.decoration is BoxDecoration &&
                          (w.decoration! as BoxDecoration).shape ==
                              BoxShape.circle,
                    ),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(dot(1).color, isNull);
    expect(
      dot(1).border,
      Border.all(color: ShellxDesktopColors.err, width: 1.5),
    );
    expect(dot(2).color, ShellxDesktopColors.ok);
    expect(dot(2).border, isNull);
  });

  testWorkspace('no driver pill for an exited tab (UI §2.5)', (tester) async {
    local.add(local.summary(1)); // phone-origin: the phone drives
    await pumpWorkspace(tester);
    expect(find.byKey(const Key('pane.driverPill')), findsOneWidget);
    local.views[1]!.end(2);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.driverPill')), findsNothing);
  });

  testWorkspace('the driver pill follows the selected tab', (tester) async {
    local.add(local.summary(1)); // the phone drives
    local.add(local.summary(2, origin: SessionOrigin.desktop));
    await pumpWorkspace(tester);
    expect(find.byKey(const Key('pane.driverPill')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab.2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.driverPill')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab.1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.driverPill')), findsOneWidget);
  });

  testWorkspace('the signed-out strip goes away once signed in (UI §2.4)', (
    tester,
  ) async {
    await pumpWorkspace(tester, signedIn: false);
    expect(find.byKey(const Key('pane.signedOutStrip')), findsOneWidget);
    await container
        .read(agentControllerProvider.notifier)
        .signIn(email: 'a@b.co', password: '12345678', register: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.signedOutStrip')), findsNothing);
  });

  testWorkspace('closing the last tab moves the keyboard to "Open new tab"', (
    tester,
  ) async {
    local.add(local.summary(1));
    await pumpWorkspace(tester);
    container.read(terminalTabsProvider.notifier).close(1);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('pane.empty')), findsOneWidget);
    expect(focusIn(find.byKey(const Key('pane.empty.open'))), isTrue);
  });

  testWorkspace('with no tabs the sidebar list is not a focus stop', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    final page = tester.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    expect(page.sidebarFocus.canRequestFocus, isFalse);
    expect(page.sidebarFocus.skipTraversal, isTrue);
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    await tester.pump();
    expect(page.sidebarFocus.canRequestFocus, isTrue);
    expect(page.sidebarFocus.skipTraversal, isFalse);
  });

  testWorkspace('a busy + is announced as not available (UI §3.2)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpWorkspace(tester);
    final plus = find.bySemanticsLabel('New tab');
    expect(
      tester.getSemantics(plus),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: true),
    );
    final gate = local.openGate = Completer<void>();
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    expect(
      tester.getSemantics(plus),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(tester.getSemantics(plus), isSemantics(isEnabled: true));
    semantics.dispose();
  });

  testWorkspace('the toast waits while its close button has keyboard focus; '
      'dismissing it gives the keyboard back to the terminal (UI §2.8)', (
    tester,
  ) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpWorkspace(tester);
    local.openError = const SessionLimitException(32);
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final closeButton = find.byKey(const Key('pane.toast.close'));
    Focus.of(
      tester.element(
        find.descendant(
          of: closeButton,
          matching: find.byType(GestureDetector),
        ),
      ),
    ).requestFocus();
    await tester.pump();
    expect(focusIn(closeButton), isTrue);
    await tester.pump(const Duration(seconds: 7));
    // Let a dismissal (if any) finish its exit animation.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('pane.toast')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.toast')), findsNothing);
    expect(focusIn(find.byKey(const ValueKey('terminal.1'))), isTrue);
  });
}
