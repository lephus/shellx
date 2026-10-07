import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/font_probe.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/config_problems_panel.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_notices.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

final class _Probe implements FontProbe {
  @override
  ({bool found, bool monospace}) probe(String family) =>
      (found: family != 'Nope', monospace: true);
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  final probe = [fontProbeProvider.overrideWithValue(_Probe())];
  const one = '1 problem in the configuration';

  testWidgets(
    'I1: a manual reload with a font that stays missing says so, not "reloaded"',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'font-family = Nope\n',
        extra: probe,
      );
      expect(find.text(one), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      await w.container.read(shellxConfigProvider.notifier).load(manual: true);
      await tester.pumpAndSettle();
      expect(find.text(one), findsOneWidget);
      expect(find.text('Configuration reloaded'), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'I1: a reload that finds the same font problem keeps the toast up',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'font-family = Nope\n',
        extra: probe,
      );
      expect(find.text(one), findsOneWidget);
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pump();
      expect(find.text(one), findsOneWidget);
      expect(find.text('Configuration reloaded'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text(one), findsOneWidget);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('the toast count follows the problems', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(
      tester,
      config: 'font-size = to\nkeybind = super+q=new_tab\n',
      extra: probe,
    );
    expect(find.text('2 problems in the configuration'), findsOneWidget);
    w.fs.write(testConfigPaths().shellx, 'font-size = to\n');
    await w.container.read(shellxConfigProvider.notifier).load();
    await tester.pumpAndSettle();
    expect(find.text(one), findsOneWidget);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'closing and reopening the window does not tell old problems again',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'font-family = Nope\nfont-size = to\n',
        extra: probe,
      );
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(workspaceApp(w.container));
      await tester.pumpAndSettle();
      expect(find.textContaining('in the configuration'), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'the Ghostty notice is not spent while the window is hidden',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester, extra: probe);
      w.container.read(windowRouterProvider.notifier).hideWindow();
      await tester.pump();
      w.fs.write(testConfigPaths().ghostty[1], 'font-family = Fira Code\n');
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(
        w.container.read(shellxConfigProvider).ghosttyNoticePending,
        isTrue,
      );
      expect(w.container.read(terminalTabsProvider).notice, isNull);
      w.container.read(windowRouterProvider.notifier).showTerminal();
      await tester.pumpAndSettle();
      expect(find.textContaining('Ghostty config'), findsOneWidget);
      expect(
        w.container.read(shellxConfigProvider).ghosttyNoticePending,
        isFalse,
      );
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'I2: the list is a focus stop before Reload; arrows scroll it',
    variant: mac,
    (tester) async {
      final lines = [
        for (var i = 0; i < 40; i++) 'bogus-key-$i = 1',
      ].join('\n');
      final w = await pumpConfiguredWorkspace(
        tester,
        config: '$lines\n',
        extra: probe,
      );
      final page = tester.state<TerminalWorkspacePageState>(
        find.byType(TerminalWorkspacePage),
      );
      page.openOverlay(A9Overlay.problems);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'problems open file',
      );
      // Open → × → list (the group wraps: list, Reload, Open, ×).
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'problems list');
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ConfigProblemsPanel),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.pixels, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final afterArrow = scrollable.position.pixels;
      expect(afterArrow, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(scrollable.position.pixels, greaterThan(afterArrow));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      // Next stop: Reload.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.text('Reload configuration'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('problems list'),
      );
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('the toast and the panel in Vietnamese', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(
      tester,
      config: 'font-size = to\n',
      extra: probe,
      locale: const Locale('vi'),
    );
    expect(find.text('Cấu hình có 1 vấn đề'), findsOneWidget);
    await tester.tap(find.text('Xem'));
    await tester.pumpAndSettle();
    expect(find.text('Vấn đề trong cấu hình'), findsOneWidget);
    expect(find.text('config, dòng 1'), findsOneWidget);
    expect(find.text('Lỗi'), findsOneWidget);
    expect(find.text('Tải lại cấu hình'), findsOneWidget);
    expect(find.text('Mở file cấu hình'), findsOneWidget);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('semantics: one node per problem, a live count', variant: mac, (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final w = await pumpConfiguredWorkspace(
      tester,
      config: 'font-size = to\n',
      extra: probe,
    );
    final page = tester.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    page.openOverlay(A9Overlay.problems);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Error, config, line 1, font-size: “to” is not valid (expected 9–28)',
      ),
      findsOneWidget,
    );
    final live = find.semantics.byLabel(one).evaluate();
    expect(live.where((n) => n.flagsCollection.isLiveRegion), isNotEmpty);
    handle.dispose();
    await disposeWorkspace(tester, w.container);
  });
}
