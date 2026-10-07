import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show EditableText, KeyEventResult;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/key_sequence.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

const ctrl = LogicalKeyboardKey.controlLeft;
const cfg = 'keybind = ctrl+a>c=new_tab\n';

Future<void> ctrlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(ctrl);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(ctrl);
  await tester.pump();
}

Future<void> ctrlA(WidgetTester tester) =>
    ctrlKey(tester, LogicalKeyboardKey.keyA);

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets(
    'prefix, then the second key runs the action; the indicator '
    'shows meanwhile',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester, config: cfg);
      final tabs = w.container.read(terminalTabsProvider).tabs.length;
      await ctrlA(tester);
      expect(w.container.read(keySequenceProvider), parseKeyChord('ctrl+a'));
      expect(find.text('⌃A …'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
      expect(w.container.read(keySequenceProvider), isNull);
      expect(find.text('⌃A …'), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('Windows labels the prefix Ctrl+A …', variant: windows, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(tester, config: cfg);
    await ctrlA(tester);
    expect(find.text('Ctrl+A …'), findsOneWidget);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'entering the wait announces once; cancelling says nothing',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester, config: cfg);
      tester.takeAnnouncements();
      await ctrlA(tester);
      await tester.pump();
      expect(tester.takeAnnouncements().map((a) => a.message), [
        '⌃A pressed, waiting for the next key',
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(tester.takeAnnouncements(), isEmpty);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'Esc cancels silently; neither key reached the shell',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester, config: cfg);
      final id = w.container.read(terminalTabsProvider).selected!.focused.id;
      await ctrlA(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(w.container.read(keySequenceProvider), isNull);
      expect(w.local.views[id]!.writes.join(), isNot(contains('\x01')));
      expect(w.local.views[id]!.writes.join(), isNot(contains('\x1b')));
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('the prefix twice types the prefix (send-prefix)', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(tester, config: cfg);
    final id = w.container.read(terminalTabsProvider).selected!.focused.id;
    await ctrlA(tester);
    await ctrlA(tester);
    expect(w.local.views[id]!.writes.join(), '\x01');
    expect(w.container.read(keySequenceProvider), isNull);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'holding the prefix sends nothing and arms it once (T9 D6)',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester, config: cfg);
      final id = w.container.read(terminalTabsProvider).selected!.focused.id;
      await tester.sendKeyDownEvent(ctrl);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyA);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(ctrl);
      await tester.pump();
      expect(w.local.views[id]!.writes, isEmpty);
      expect(w.container.read(keySequenceProvider), parseKeyChord('ctrl+a'));
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'another key cancels and goes on as usual: to the shell',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester, config: cfg);
      final id = w.container.read(terminalTabsProvider).selected!.focused.id;
      final tabs = w.container.read(terminalTabsProvider).tabs.length;
      await ctrlA(tester);
      // Ctrl+E is not a second step: the sequence ends and the key reaches
      // the shell as xterm encodes it (^E).
      await ctrlKey(tester, LogicalKeyboardKey.keyE);
      expect(w.container.read(keySequenceProvider), isNull);
      expect(w.local.views[id]!.writes.join(), '\x05');
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'another key cancels and goes on as usual: to another shortcut',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester, config: cfg);
      final tabs = w.container.read(terminalTabsProvider).tabs.length;
      await ctrlA(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT); // new tab
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(w.container.read(keySequenceProvider), isNull);
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a prefix drops only the single chord it shadows (D27)',
    variant: mac,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config:
            'keybind = ctrl+a=new_tab\nkeybind = ctrl+a>c=new_tab\n'
            'keybind = ctrl+shift+a=new_tab\n',
      );
      expect(
        w.container.read(shellxConfigProvider).problems.map((p) => p.code),
        contains(ConfigProblemCode.sequencePrefixShadows),
      );
      final tabs = w.container.read(terminalTabsProvider).tabs.length;
      await ctrlA(tester); // starts the sequence, not a tab
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs);
      expect(w.container.read(keySequenceProvider), isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      // The same first key with Shift is a different chord: still a binding.
      await tester.sendKeyDownEvent(ctrl);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(ctrl);
      await tester.pumpAndSettle();
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'AltGr yields: neither starts nor finishes a sequence (D26)',
    variant: windows,
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config:
            'keybind = ctrl+alt+a>c=new_tab\nkeybind = ctrl+a>ctrl+alt+q=new_tab\n',
      );
      final tabs = w.container.read(terminalTabsProvider).tabs.length;
      // AltGr+A would be the prefix of the first sequence.
      await tester.sendKeyDownEvent(ctrl);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyUpEvent(ctrl);
      await tester.pump();
      expect(w.container.read(keySequenceProvider), isNull);
      // A real prefix, then AltGr+Q: the layout's character, no tab.
      await ctrlA(tester);
      expect(w.container.read(keySequenceProvider), isNotNull);
      await tester.sendKeyDownEvent(ctrl);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyUpEvent(ctrl);
      await tester.pump();
      expect(w.container.read(keySequenceProvider), isNull);
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs);
      // The same second step with the left Alt runs.
      await ctrlA(tester);
      await tester.sendKeyDownEvent(ctrl);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(ctrl);
      await tester.pumpAndSettle();
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'an input method key neither swallows nor ends nothing: the '
    'composition goes on',
    variant: windows,
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester, config: cfg);
      await ctrlA(tester);
      expect(w.container.read(keySequenceProvider), isNotNull);
      // The test keyboard cannot make the key itself: hand the handler one.
      final handled = w.container
          .read(keySequenceProvider.notifier)
          .handle(
            const KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.keyA,
              logicalKey: LogicalKeyboardKey.process,
              timeStamp: Duration.zero,
            ),
            invoke: (_) => true,
            sendPrefix: (_) {},
          );
      await tester.pump();
      expect(handled, KeyEventResult.ignored);
      expect(w.container.read(keySequenceProvider), isNull);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('a text field keeps Ctrl+A (D28)', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: cfg);
    // Ctrl+F6: terminal → sidebar (plain F6 is the shell's inside a pane);
    // then F2 on the selected row opens A2's inline rename field.
    await ctrlKey(tester, LogicalKeyboardKey.f6);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    await ctrlA(tester);
    expect(w.container.read(keySequenceProvider), isNull);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('the sidebar has sequences too', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: cfg);
    final tabs = w.container.read(terminalTabsProvider).tabs.length;
    await ctrlKey(tester, LogicalKeyboardKey.f6); // the sidebar
    await ctrlA(tester);
    expect(w.container.read(keySequenceProvider), isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('a click cancels', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: cfg);
    await ctrlA(tester);
    await tester.tapAt(const Offset(600, 300));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(w.container.read(keySequenceProvider), isNull);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('a focus change cancels', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: cfg);
    await ctrlA(tester);
    await ctrlKey(tester, LogicalKeyboardKey.f6); // terminal → sidebar
    await tester.pump();
    expect(w.container.read(keySequenceProvider), isNull);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('a reload cancels a pending sequence', variant: mac, (
    tester,
  ) async {
    final w = await pumpConfiguredWorkspace(tester, config: cfg);
    await ctrlA(tester);
    w.fs.write(testConfigPaths().shellx, 'keybind = ctrl+a>d=new_tab\n');
    await loadConfig(w.container);
    await tester.pump();
    expect(w.container.read(keySequenceProvider), isNull);
    await disposeWorkspace(tester, w.container);
  });

  test('prefixText', () {
    expect(prefixText(parseKeyChord('ctrl+a')!), '\x01');
    expect(prefixText(parseKeyChord('ctrl+b')!), '\x02');
    expect(prefixText(parseKeyChord('alt+a')!), '\x1ba');
    expect(prefixText(parseKeyChord('super+a')!), isNull);
    expect(prefixText(parseKeyChord('ctrl+shift+a')!), isNull);
  });
}
