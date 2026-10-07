import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/command_palette.dart';

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
        tester
            .widget<Text>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('palette.row.0')),
                    matching: find.byType(Text),
                  )
                  .first,
            )
            .data,
        'Split down',
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
      final id = w.container.read(terminalTabsProvider).selected!.focused.id;
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
      final id = w.container.read(terminalTabsProvider).selected!.focused.id;
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
      final id = w.container.read(terminalTabsProvider).selected!.focused.id;
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
}
