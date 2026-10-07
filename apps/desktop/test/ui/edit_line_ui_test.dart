import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_workspace.dart';

Future<void> chord(
  WidgetTester t,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool alt = false,
}) async {
  if (meta) await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (alt) await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await t.sendKeyEvent(key);
  if (alt) await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (meta) await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pump();
}

void main() {
  testWidgets(
    '⌘← ⌘→ ⌘⌫ ⌥⌫ ⌥⌦ write the shell keys to the focused pane',
    (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final tab = c.read(terminalTabsProvider).selected!;
      final writes = rig.local.views[tab.focusedPaneId]!.writes;
      writes.clear();
      await chord(t, LogicalKeyboardKey.arrowLeft, meta: true);
      await chord(t, LogicalKeyboardKey.arrowRight, meta: true);
      await chord(t, LogicalKeyboardKey.backspace, meta: true);
      await chord(t, LogicalKeyboardKey.backspace, alt: true);
      await chord(t, LogicalKeyboardKey.delete, alt: true);
      expect(writes.join(), '\x01\x05\x15\x1b\x7f\x1bd');
      await disposeWorkspace(t, c);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'on the alternate screen (vim) the keys are not taken',
    (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final tab = c.read(terminalTabsProvider).selected!;
      tab.terminal.write('\x1b[?1049h'); // vim switches to the alternate screen
      final writes = rig.local.views[tab.focusedPaneId]!.writes;
      writes.clear();
      await chord(t, LogicalKeyboardKey.arrowLeft, meta: true);
      expect(writes.join().contains('\x01'), isFalse);
      await disposeWorkspace(t, c);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'while an input method composes (Telex) ⌥⌫ is the IME\'s',
    (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final tab = c.read(terminalTabsProvider).selected!;
      final writes = rig.local.views[tab.focusedPaneId]!.writes;
      t.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'a',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await t.pump();
      writes.clear();
      await chord(t, LogicalKeyboardKey.backspace, alt: true);
      expect(writes.join().contains('\x1b\x7f'), isFalse);
      await disposeWorkspace(t, c);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
