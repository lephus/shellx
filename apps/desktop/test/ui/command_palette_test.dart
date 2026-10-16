import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/command_palette.dart';

import 'package:shellx_desktop/src/config/config_controller.dart';
import '../support/config_harness.dart';
import '../support/config_workspace.dart';

const cmd = LogicalKeyboardKey.metaLeft;
const shift = LogicalKeyboardKey.shiftLeft;

Future<void> openPalette(WidgetTester tester) async {
  await tester.sendKeyDownEvent(cmd);
  await tester.sendKeyDownEvent(shift);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(shift);
  await tester.sendKeyUpEvent(cmd);
  await tester.pumpAndSettle();
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets(
    '⌘⇧P, type, Enter runs; the keyboard returns to the terminal (criterion 7)',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      await openPalette(tester);
      expect(find.byType(CommandPalette), findsOneWidget);
      expect(find.bySemanticsLabel('Search commands'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'split d');
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(const ValueKey('palette.row.0'))).label,
        startsWith('Split down'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsNothing);
      expect(w.container.read(terminalTabsProvider).selected!.paneCount, 2);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'hidden when not applicable; commands run in the focused pane',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'command = Lint = npm run lint\n',
      );
      await openPalette(tester);
      expect(find.text('Zoom or unzoom pane'), findsNothing); // one pane
      await tester.enterText(find.byType(TextField), 'lint');
      await tester.pumpAndSettle();
      expect(find.text('Your command'), findsOneWidget);
      expect(find.text('npm run lint'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final id = w.container.read(terminalTabsProvider).selected!.focused!.id;
      expect(w.local.views[id]!.writes.join(), 'npm run lint\r');
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'Esc clears, then closes; ↓ wraps; ⌘⇧P closes too',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'tab');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.byType(CommandPalette), findsOneWidget);
      await tester.sendKeyEvent(
        LogicalKeyboardKey.arrowUp,
      ); // wraps to the last
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsNothing);
      await openPalette(tester);
      await openPalette(tester);
      expect(find.byType(CommandPalette), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('a problem adds "Show configuration problems"', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'font-size = x\n');
    await openPalette(tester);
    expect(find.text('Show configuration problems'), findsOneWidget);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'Cmd+V pastes into the field, never into the terminal',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => switch (call.method) {
          'Clipboard.getData' => <String, dynamic>{'text': 'hello'},
          'Clipboard.hasStrings' => <String, dynamic>{'value': true},
          _ => null,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openPalette(tester);
      await tester.sendKeyDownEvent(cmd);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(cmd);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'hello',
      );
      final id = w.container.read(terminalTabsProvider).selected!.focused!.id;
      expect(w.local.views[id]!.writes, isEmpty);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'Enter while an input method composes does not run the entry',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      await openPalette(tester);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'tab',
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pumpAndSettle();
      final before = w.container.read(terminalTabsProvider).tabs.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      expect(w.container.read(terminalTabsProvider).tabs.length, before);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('Esc returns the keyboard to where it was', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(tester);
    final before = FocusManager.instance.primaryFocus;
    await openPalette(tester);
    expect(FocusManager.instance.primaryFocus, isNot(same(before)));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    expect(FocusManager.instance.primaryFocus, same(before));
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'Vietnamese labels, matched without marks; no match says so',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        locale: const Locale('vi'),
      );
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'chia xuong');
      await tester.pumpAndSettle();
      expect(find.text('Chia xuống dưới'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Không có lệnh nào khớp'), findsOneWidget);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a snippet is pasted without Enter; no problem, no problems entry',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'snippet = Note = hello\n',
      );
      await openPalette(tester);
      expect(find.text('Show configuration problems'), findsNothing);
      await tester.enterText(find.byType(TextField), 'note');
      await tester.pumpAndSettle();
      expect(find.text('Snippet'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final id = w.container.read(terminalTabsProvider).selected!.focused!.id;
      expect(w.local.views[id]!.writes.join(), 'hello');
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'the selected entry is exposed as selected; the list as a list',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      await openPalette(tester);
      final handle = tester.ensureSemantics();
      final first = tester.getSemantics(
        find.byKey(const ValueKey('palette.row.0')),
      );
      final second = tester.getSemantics(
        find.byKey(const ValueKey('palette.row.1')),
      );
      expect(first.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(second.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));
      expect(first.label, isNotEmpty);
      handle.dispose();
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'AltGr (Ctrl + right Alt) + Shift + P does not open it on Windows',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyDownEvent(shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'Tab and Shift+Tab keep the keyboard in the field',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      await openPalette(tester);
      bool inField() =>
          tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;
      expect(inField(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(inField(), isTrue);
      await tester.sendKeyDownEvent(shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(shift);
      await tester.pumpAndSettle();
      expect(inField(), isTrue);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'Esc while an input method composes keeps the palette open',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      await openPalette(tester);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'tab',
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('composing Enter writes nothing to the terminal', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(
      tester,
      config: 'command = Lint = npm run lint\n',
    );
    await openPalette(tester);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'lint',
        composing: TextRange(start: 0, end: 4),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsOneWidget);
    final id = w.container.read(terminalTabsProvider).selected!.focused!.id;
    expect(w.local.views[id]!.writes, isEmpty);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'Ctrl+Shift+V pastes into the field on Windows',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => switch (call.method) {
          'Clipboard.getData' => <String, dynamic>{'text': 'hello'},
          'Clipboard.hasStrings' => <String, dynamic>{'value': true},
          _ => null,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'hello',
      );
      final id = w.container.read(terminalTabsProvider).selected!.focused!.id;
      expect(w.local.views[id]!.writes, isEmpty);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'Paste is listed with a tab and hidden without one',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'paste');
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      w.container
          .read(terminalTabsProvider.notifier)
          .close(w.container.read(terminalTabsProvider).selectedId!);
      await tester.pumpAndSettle();
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'paste');
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      expect(find.text('Paste'), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'the matched letters are highlighted, marks and all',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        locale: const Locale('vi'),
      );
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'chia');
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey('palette.row.0')),
              matching: find.byType(Text),
            )
            .first,
      );
      final spans = text.textSpan!.toPlainText();
      expect(spans, startsWith('Chia'));
      final bold = <String>[];
      text.textSpan!.visitChildren((s) {
        if (s is TextSpan && s.style?.fontWeight == FontWeight.w600) {
          bold.add(s.text!);
        }
        return true;
      });
      expect(bold.join(), 'Chia');
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a reload that removes a command while open removes its row',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'command = Lint = npm run lint\n',
      );
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'lint');
      await tester.pumpAndSettle();
      expect(find.text('Lint'), findsOneWidget);
      w.fs.write(testConfigPaths().shellx, '');
      await w.container.read(shellxConfigProvider.notifier).load(manual: true);
      await tester.pumpAndSettle();
      expect(find.text('Lint'), findsNothing);
      expect(find.byType(CommandPalette), findsOneWidget);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('arrows with a modifier do not move the list', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(tester);
    await openPalette(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    final first = tester.getSemantics(
      find.byKey(const ValueKey('palette.row.0')),
    );
    expect(first.flagsCollection.isSelected, ui.Tristate.isTrue);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'the result count is read once after typing settles',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      final handle = tester.ensureSemantics();
      await openPalette(tester);
      tester.takeAnnouncements();
      await tester.enterText(find.byType(TextField), 't');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'ta');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'tab');
      await tester.pump(const Duration(milliseconds: 700));
      final counts = tester
          .takeAnnouncements()
          .map((a) => a.message)
          .where((m) => m.endsWith('commands') || m.endsWith('command'));
      expect(counts, hasLength(1));
      handle.dispose();
      await disposeWorkspace(tester, w.container);
    },
  );
}
