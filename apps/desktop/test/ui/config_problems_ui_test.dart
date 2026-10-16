import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/font_probe.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/action_labels.dart';
import 'package:shellx_desktop/src/ui/config/config_problems_panel.dart';
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/terminal/key_sequence.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_notices.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

/// The engine's test font is one font for everything: probe by name.
final class _Probe implements FontProbe {
  _Probe(this.missing);
  final Set<String> missing;
  @override
  ({bool found, bool monospace}) probe(String family) =>
      (found: !missing.contains(family), monospace: true);
}

void main() {
  test('the en ARB says exactly what the CLI says (D39)', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final vi = lookupAppLocalizations(const Locale('vi'));
    for (final code in ConfigProblemCode.values) {
      final p = ConfigProblem(
        file: '/c/config',
        line: 2,
        severity: ConfigSeverity.error,
        code: code,
        key: 'font-size',
        value: 'to',
        hint: '9–28',
        detail: '4.1',
      );
      expect(problemText(en, p), configProblemEnglish(p), reason: code.name);
      expect(problemText(vi, p), isNot(contains('{')), reason: code.name);
      expect(problemText(vi, p), isNotEmpty, reason: code.name);
    }
    final p = ConfigProblem(
      file: '/c/config',
      line: 3,
      severity: ConfigSeverity.error,
      code: ConfigProblemCode.syntax,
    );
    expect(problemLocation(en, p), 'config, line 3');
    expect(problemLocation(vi, p), 'config, dòng 3');
    expect(
      problemLocation(
        en,
        ConfigProblem(
          file: '/c/config',
          line: 0,
          severity: ConfigSeverity.error,
          code: ConfigProblemCode.unreadable,
        ),
      ),
      'config',
    );
  });

  test('a problem with no file path renders without one', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final vi = lookupAppLocalizations(const Locale('vi'));
    ConfigProblem at(int line) => ConfigProblem(
      file: '',
      line: line,
      severity: ConfigSeverity.error,
      code: ConfigProblemCode.internal,
    );
    expect(problemLocation(en, at(0)), '');
    expect(problemLocation(en, at(4)), 'line 4');
    expect(problemLocation(vi, at(4)), 'dòng 4');
  });

  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  final probe = [
    fontProbeProvider.overrideWithValue(_Probe({'Nope'})),
  ];

  testWidgets(
    'an error raises an error toast; Show opens the panel (criterion 4)',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'font-size = to\nkeybind = super+q=new_tab\n',
        extra: probe,
      );
      expect(find.text('2 problems in the configuration'), findsOneWidget);
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(find.byType(ConfigProblemsPanel), findsOneWidget);
      expect(find.text('config, line 1'), findsOneWidget);
      expect(
        find.text('font-size: “to” is not valid (expected 9–28)'),
        findsOneWidget,
      );
      expect(find.text('⌘Q is reserved by the system'), findsOneWidget);
      // Fixing the file and reloading empties the panel in place.
      w.fs.write(testConfigPaths().shellx, 'font-size = 14\n');
      await tester.tap(find.text('Reload configuration'));
      await tester.pumpAndSettle();
      expect(find.text('No problems in the configuration.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ConfigProblemsPanel), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'notes alone raise no toast; a manual reload says so',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'keybind = ctrl+c=new_tab\n',
        extra: probe,
      );
      expect(find.textContaining('in the configuration'), findsNothing);
      await w.container.read(shellxConfigProvider.notifier).load(manual: true);
      await tester.pumpAndSettle();
      expect(find.text('Configuration reloaded'), findsOneWidget);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'the same problems again raise no second toast; a fix dismisses it',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'font-size = to\n',
        extra: probe,
      );
      final notifier = w.container.read(shellxConfigProvider.notifier);
      await tester.tap(find.byTooltip('Dismiss')); // the toast ×
      await tester.pumpAndSettle();
      await notifier.load();
      await tester.pumpAndSettle();
      expect(find.text('1 problem in the configuration'), findsNothing);
      w.fs.write(testConfigPaths().shellx, 'font-size = 20\nfont-size = x\n');
      await notifier.load();
      await tester.pumpAndSettle();
      expect(find.text('1 problem in the configuration'), findsOneWidget);
      w.fs.write(testConfigPaths().shellx, 'font-size = 20\n');
      await notifier.load();
      await tester.pumpAndSettle();
      expect(find.textContaining('in the configuration'), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a problem that stays (Ghostty colour names) is not a toast on every '
    'reload',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester, extra: probe);
      w.container.read(terminalTabsProvider.notifier).dismissNotice();
      w.fs.write(testConfigPaths().ghostty[1], 'background = black\n');
      final notifier = w.container.read(shellxConfigProvider.notifier);
      await notifier.load();
      await tester.pumpAndSettle();
      final state = w.container.read(shellxConfigProvider);
      expect(state.visibleProblemCount, greaterThan(0));
      expect(find.textContaining('in the configuration'), findsOneWidget);
      // The user closes it; every later reload (the watcher's, a touch of
      // the file) finds the same problem and says nothing.
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        w.fs.write(testConfigPaths().ghostty[1], 'background = black\n# $i\n');
        await notifier.load();
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('in the configuration'), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a missing font is told once, not on every reload',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'font-family = Nope\n',
        extra: probe,
      );
      expect(find.text('1 problem in the configuration'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      final notifier = w.container.read(shellxConfigProvider.notifier);
      await notifier.load();
      await tester.pumpAndSettle();
      expect(find.textContaining('in the configuration'), findsNothing);
      // Fixed, then broken again: told again.
      w.fs.write(testConfigPaths().shellx, 'font-family = Menlo\n');
      await notifier.load();
      await tester.pumpAndSettle();
      w.fs.write(testConfigPaths().shellx, 'font-family = Nope\n');
      await notifier.load();
      await tester.pumpAndSettle();
      expect(find.text('1 problem in the configuration'), findsOneWidget);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('Ghostty: a one-time neutral notice (D4)', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(tester, extra: probe);
    expect(w.container.read(shellxConfigProvider).ghosttyNoticePending, false);
    w.fs.write(testConfigPaths().ghostty[1], 'font-family = Fira Code\n');
    await w.container.read(shellxConfigProvider.notifier).load();
    await tester.pumpAndSettle();
    expect(find.textContaining('Ghostty config'), findsOneWidget);
    // Acknowledged once shown: never due again.
    expect(w.container.read(shellxConfigProvider).ghosttyNoticePending, false);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'the Ghostty notice waits behind a problems toast and is not lost',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'font-size = to\n',
        extra: probe,
      );
      w.fs.write(testConfigPaths().ghostty[1], 'font-family = Fira Code\n');
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(find.text('1 problem in the configuration'), findsOneWidget);
      expect(find.textContaining('Ghostty config'), findsNothing);
      expect(
        w.container.read(shellxConfigProvider).ghosttyNoticePending,
        isTrue,
      );
      await tester.tap(find.byTooltip('Dismiss'));
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
    'closePanel closes the problems overlay; so does another window shortcut',
    variant: mac,
    (tester) async {
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
      expect(find.byType(ConfigProblemsPanel), findsOneWidget);
      page.closePanel();
      await tester.pumpAndSettle();
      expect(find.byType(ConfigProblemsPanel), findsNothing);
      // The notifications panel (⌘⇧I) takes over from the overlay.
      page.openOverlay(A9Overlay.problems);
      await tester.pumpAndSettle();
      page.togglePanel();
      await tester.pumpAndSettle();
      expect(find.byType(ConfigProblemsPanel), findsNothing);
      expect(page.panelOpen, isTrue);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'opening the overlay ends a pending key sequence and Esc returns the '
    'keyboard',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'font-size = to\nkeybind = ctrl+a>c=new_tab\n',
        extra: probe,
      );
      final page = tester.state<TerminalWorkspacePageState>(
        find.byType(TerminalWorkspacePage),
      );
      final before = FocusManager.instance.primaryFocus;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(w.container.read(keySequenceProvider), isNotNull);
      page.openOverlay(A9Overlay.problems);
      await tester.pumpAndSettle();
      expect(w.container.read(keySequenceProvider), isNull);
      // The primary button has the keyboard.
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'problems open file',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ConfigProblemsPanel), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(before));
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('a tray request opens the problems panel', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(tester, extra: probe);
    expect(find.byType(ConfigProblemsPanel), findsNothing);
    w.container
        .read(configUiRequestProvider.notifier)
        .request(ConfigUiRequest.problems);
    await tester.pumpAndSettle();
    expect(find.byType(ConfigProblemsPanel), findsOneWidget);
    expect(find.text('No problems in the configuration.'), findsOneWidget);
    await disposeWorkspace(tester, w.container);
  });
}
