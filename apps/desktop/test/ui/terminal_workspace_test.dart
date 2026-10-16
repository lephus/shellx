import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/clipboard_media.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_overlays.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

late TestHarness h;
late FakeLocalSessions local;
late ProviderContainer container;

Future<void> pumpWorkspace(
  WidgetTester tester, {
  bool signedIn = true,
  Size size = const Size(1100, 720),
}) async {
  h = TestHarness(settings: {'onboarding_done': true});
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
      clipboardMediaProvider.overrideWithValue(const EmptyClipboardMedia()),
      // A10 D20: these tests check layout, not settling: sizes go at once.
      resizeSettleProvider.overrideWithValue(Duration.zero),
    ],
  );
  if (signedIn) await h.seedSignedIn();
  await container
      .read(agentControllerProvider.notifier)
      .bootstrap(watchForWake: false);
  tester.view.physicalSize = size;
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

TerminalWorkspacePageState page(WidgetTester tester) => tester
    .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage));

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
      find.descendant(of: phoneRow, matching: find.byIcon(kPhoneIcon)),
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
        matching: find.byIcon(kPhoneIcon),
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

  group('row close button (ruling I6)', () {
    Finder close(int id) => find.descendant(
      of: find.byKey(ValueKey('tab.$id')),
      matching: find.byKey(const Key('row.close')),
    );

    testWorkspace('shows on the selected row and on hover only; its slot is '
        'always kept', (tester) async {
      local.add(local.summary(1, origin: SessionOrigin.desktop));
      local.add(local.summary(2));
      await pumpWorkspace(tester);
      expect(close(1).hitTestable(), findsOneWidget); // selected
      expect(close(2).hitTestable(), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tab.2')),
          matching: find.byKey(const Key('row.close')),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(
        location: tester.getCenter(find.byKey(const ValueKey('tab.2'))),
      );
      await tester.pump();
      expect(close(2).hitTestable(), findsOneWidget);
      expect(tester.getSize(close(2)), const Size(24, 24));
    });

    testWorkspace('closes an idle tab at once, without selecting it', (
      tester,
    ) async {
      local.add(local.summary(1, origin: SessionOrigin.desktop));
      await pumpWorkspace(tester);
      await tester.tap(close(1));
      await tester.pump();
      expect(local.closed, [1]);
    });

    testWorkspace('a running command asks first (D15)', (tester) async {
      local.add(local.summary(1, title: 'claude', runningCommand: true));
      await pumpWorkspace(tester);
      await tester.tap(close(1));
      await tester.pump();
      final confirm = container.read(windowRouterProvider).confirm!;
      expect(confirm.title, 'Close “claude”?');
      confirm.complete(false);
      await tester.pump();
      expect(local.closed, isEmpty);
    });
  });

  testWorkspace('the three status dots differ in shape, not only colour '
      '(S-3)', (tester) async {
    local.add(local.summary(1));
    local.add(local.summary(2, runningCommand: true));
    local.add(local.summary(3));
    await pumpWorkspace(tester);
    local.views[3]!.end(1);
    await tester.pump();
    await tester.pump();
    Finder dot(int id, String kind) => find.descendant(
      of: find.byKey(ValueKey('tab.$id')),
      matching: find.byKey(Key('dot.$kind')),
    );
    expect(dot(1, 'idle'), findsOneWidget);
    expect(dot(2, 'running'), findsOneWidget);
    expect(dot(3, 'exited'), findsOneWidget);
    final running = tester.widget<Container>(dot(2, 'running'));
    expect(
      (running.decoration! as BoxDecoration).border,
      Border.all(color: ShellxDesktopColors.accent, width: 1.5),
    );
    // A 4 px filled centre makes it a target.
    expect(
      find.descendant(
        of: dot(2, 'running'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              (w.decoration as BoxDecoration?)?.color ==
                  ShellxDesktopColors.accent,
        ),
      ),
      findsOneWidget,
    );
  });

  testWorkspace('the selected bar is 3×18 and moves inside the keyboard ring '
      '(S-7)', (tester) async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    await pumpWorkspace(tester);
    final bar = find.byKey(const Key('row.selectedBar'));
    expect(tester.getSize(bar), const Size(3, 18));
    final row = tester.getTopLeft(find.byKey(const ValueKey('tab.1')));
    expect(tester.getTopLeft(bar).dx - row.dx, 0);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    page(tester).sidebarFocus.requestFocus();
    await tester.pump();
    expect(tester.getTopLeft(bar).dx - row.dx, 3);
  });

  testWorkspace('a cut title shows its tooltip beside the sidebar, not over '
      'the next row (S-8)', (tester) async {
    local.add(local.summary(1, title: 'a' * 80));
    local.add(local.summary(2));
    await pumpWorkspace(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('a' * 80)));
    await tester.pump(const Duration(seconds: 1));
    final tooltip = find
        .byType(Tooltip)
        .evaluate()
        .where((e) => (e.widget as Tooltip).message == 'a' * 80);
    expect(tooltip, hasLength(1));
    final label = find.text('a' * 80).last; // the tooltip's own text
    final box = tester.getRect(label);
    expect(box.left, greaterThanOrEqualTo(226));
    final row1 = tester.getRect(find.byKey(const ValueKey('tab.1')));
    expect(box.center.dy, closeTo(row1.center.dy, 2));
    expect(box.width, lessThanOrEqualTo(360));
  });

  group('terminal context menu (ruling I6)', () {
    Future<void> rightClick(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey('terminal.1')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
    }

    PopupMenuItem<Object?> item(WidgetTester tester, String key) =>
        tester.widget<PopupMenuItem<Object?>>(find.byKey(Key(key)));

    testWorkspace('Copy is disabled without a selection; Paste pastes', (
      tester,
    ) async {
      local.add(local.summary(1, origin: SessionOrigin.desktop));
      await pumpWorkspace(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': 'echo hi'} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await rightClick(tester);
      expect(find.text('Copy'), findsOneWidget);
      expect(item(tester, 'menu.copy').enabled, isFalse);
      expect(item(tester, 'menu.paste').enabled, isTrue);
      expect(find.text('Select all'), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu.paste')));
      await tester.pumpAndSettle();
      expect(local.views[1]!.writes, ['echo hi']);
    });

    testWorkspace('Select all selects the scrollback too; then Copy is '
        'enabled and copies', (tester) async {
      local.add(
        local.summary(1, origin: SessionOrigin.desktop),
        backlog: 'first\r\nsecond\r\n',
      );
      await pumpWorkspace(tester);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await rightClick(tester);
      await tester.tap(find.byKey(const Key('menu.selectAll')));
      await tester.pumpAndSettle();
      expect(tabs().selected!.selection!.selection, isNotNull);
      await rightClick(tester);
      expect(item(tester, 'menu.copy').enabled, isTrue);
      await tester.tap(find.byKey(const Key('menu.copy')));
      await tester.pumpAndSettle();
      expect(copied, contains('first'));
      expect(copied, contains('second'));
      // The keyboard is back in the terminal.
      expect(focusIn(find.byKey(const ValueKey('terminal.1'))), isTrue);
    });
  });

  testWorkspace(
    '⌘A / Ctrl+Shift+A selects all only while the terminal has '
    'the keyboard',
    (tester) async {
      local.add(
        local.summary(1, origin: SessionOrigin.desktop),
        backlog: 'first\r\n',
      );
      await pumpWorkspace(tester);
      final mac = defaultTargetPlatform == TargetPlatform.macOS;
      Future<void> selectAll() async {
        await tester.sendKeyDownEvent(
          mac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
        );
        if (!mac) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        if (!mac) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(
          mac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
        );
        await tester.pump();
      }

      page(tester).sidebarFocus.requestFocus();
      await tester.pump();
      await selectAll();
      expect(tabs().selected!.selection!.selection, isNull);
      page(tester).terminalFocus.requestFocus();
      await tester.pump();
      await selectAll();
      expect(tabs().selected!.selection!.selection, isNotNull);
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  group('driver pill placement (S-1, S-2)', () {
    Rect pill(WidgetTester tester) =>
        tester.getRect(find.byKey(const Key('pane.driverPill')));
    Rect pane(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey('terminal.1')));

    testWorkspace('top-right while the cursor is lower down', (tester) async {
      local.add(
        local.summary(1, attachedMobileId: 'm1'),
        backlog: 'a\r\nb\r\nc\r\nd\r\n\$ ',
      );
      await pumpWorkspace(tester);
      final p = pill(tester);
      expect(pane(tester).right - p.right, 12);
      expect(p.top - pane(tester).top, 8);
    });

    testWorkspace('bottom-right when the prompt is on the first row, so it '
        'never hides the line being typed', (tester) async {
      local.add(local.summary(1, attachedMobileId: 'm1'), backlog: r'$ ');
      await pumpWorkspace(tester);
      final p = pill(tester);
      expect(pane(tester).right - p.right, 12);
      expect(pane(tester).bottom - p.bottom, 8);
      // Output moves the cursor down: back to the top.
      local.views[1]!.emit('\r\n1\r\n2\r\n3\r\n\$ ');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(pill(tester).top - pane(tester).top, 8);
    });

    testWorkspace('a narrow pane gets the short copy, uncut', (tester) async {
      local.add(
        local.summary(1, attachedMobileId: 'm1'),
        backlog: 'a\r\nb\r\nc\r\nd\r\n',
      );
      await pumpWorkspace(tester, size: const Size(640, 400));
      expect(find.text('Phone in control — type to take over'), findsOneWidget);
      final text = tester.renderObject<RenderParagraph>(
        find.text('Phone in control — type to take over'),
      );
      expect(text.didExceedMaxLines, isFalse);
    });
  });

  testWorkspace('640×400 signed out: the terminal is clipped below the strip '
      'and starts on its first line (M-1)', (tester) async {
    local.add(
      local.summary(1, origin: SessionOrigin.desktop),
      backlog: 'first line\r\nsecond\r\n\$ ',
    );
    await pumpWorkspace(tester, signedIn: false, size: const Size(640, 400));
    final view = find.byKey(const ValueKey('terminal.1'));
    expect(
      find.descendant(of: view, matching: find.byType(ClipRect)),
      findsWidgets,
    );
    final strip = tester.getRect(find.byKey(const Key('pane.signedOutStrip')));
    expect(tester.getRect(view).top, greaterThanOrEqualTo(strip.bottom));
    final scroll = tester
        .widget<TerminalView>(
          find.descendant(of: view, matching: find.byType(TerminalView)),
        )
        .scrollController!;
    expect(scroll.offset, 0);
    expect(
      tabs().selected!.terminal!.buffer.getText(),
      startsWith('first line'),
    );
  });

  testWorkspace('a keyboard-focused filled button draws its ring outside '
      'the fill (S-9)', (tester) async {
    await pumpWorkspace(tester);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await tester.pump();
    final button = find.byKey(const Key('pane.empty.open'));
    expect(focusIn(button), isTrue);
    final material = tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)).first,
    );
    expect(material.shape, isA<OutsideFocusRingBorder>());
  });

  testWorkspace('a deleted-workspace notice is a neutral toast; a port '
      'failure an error toast (UI-A2 §7)', (tester) async {
    await pumpWorkspace(tester);
    container
        .read(terminalTabsProvider.notifier)
        .showNotice(
          const WorkspaceDeletedNotice(name: 'Ops', movedTo: 'Default'),
        );
    await tester.pump();
    expect(
      find.text('Deleted workspace “Ops”. Its tabs moved to Default.'),
      findsOneWidget,
    );
    final box = tester.widget<Container>(find.byKey(const Key('pane.toast')));
    expect(
      (box.decoration! as BoxDecoration).color,
      ShellxDesktopColors.rowSelected,
    );
    container
        .read(terminalTabsProvider.notifier)
        .showNotice(const PortOpenFailedNotice());
    await tester.pump();
    expect(find.text("Couldn't open the browser."), findsOneWidget);
  });

  testWorkspace(
    '⌘⇧N makes a workspace with a tab; ⌘1 and ↓ in the list follow the '
    'visible order (C5)',
    (tester) async {
      local
        ..add(local.summary(1, origin: SessionOrigin.desktop))
        ..add(local.summary(2, origin: SessionOrigin.desktop));
      await pumpWorkspace(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      final sidebar = container.read(sidebarWorkspacesProvider);
      expect(sidebar.workspaces, hasLength(2));
      final ws = sidebar.workspaces.last.id;
      final created = sidebar.tabsOf(ws).single;
      container.read(sidebarWorkspacesProvider.notifier)
        ..endRename()
        ..setCollapsed(kDefaultWorkspaceId, true);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(tabs().selectedId, created);
      expect(find.byKey(const ValueKey('tab.1')), findsNothing); // collapsed

      // ↓ and Home in the list: Default [2, 1], then the new tab — not the
      // creation order 1, 2, new.
      container.read(sidebarWorkspacesProvider.notifier)
        ..setCollapsed(kDefaultWorkspaceId, false)
        ..moveTab(1, kDefaultWorkspaceId);
      container.read(terminalTabsProvider.notifier).select(2);
      await tester.pump(); // the selection hands the terminal the focus
      page(tester).sidebarFocus.requestFocus();
      await tester.pump();
      expect(page(tester).sidebarFocus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tabs().selectedId, 1);
      // Home is the tree's first node, Default's header (D14, UI-A2 §8):
      // the tab stays; ↓ then reaches Default's first row.
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(tabs().selectedId, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tabs().selectedId, 2);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
