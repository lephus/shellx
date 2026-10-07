import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Key, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_opener.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/command_palette.dart';
import 'package:shellx_desktop/src/ui/config/config_problems_panel.dart';
import 'package:shellx_desktop/src/ui/terminal/shortcut_labels.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

Future<void> chord(
  WidgetTester tester,
  List<LogicalKeyboardKey> mods,
  LogicalKeyboardKey key,
) async {
  for (final m in mods) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final m in mods.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pumpAndSettle();
}

const cmd = LogicalKeyboardKey.metaLeft;
const shift = LogicalKeyboardKey.shiftLeft;
const ctrl = LogicalKeyboardKey.controlLeft;
const alt = LogicalKeyboardKey.altLeft;

final class RecordingOpener implements ConfigFileOpener {
  RecordingOpener({this.succeed = true});
  final bool succeed;
  final opened = <String>[];
  @override
  bool get windows => false;
  @override
  Future<bool> open(String path, {required String Function() template}) async {
    opened.add(path);
    return succeed;
  }
}

void main() {
  testWidgets(
    'a custom chord splits; the default still works; labels follow (criterion 5)',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config:
            'keybind = super+shift+t=new_split:down\nkeybind = super+shift+d=unbind\n',
      );
      expect(splitDownShortcutLabel(), '⌘⇧T');
      await chord(tester, [cmd, shift], LogicalKeyboardKey.keyT);
      final tab = w.container.read(terminalTabsProvider).selected!;
      expect(tab.isSplit, isTrue);
      expect((tab.layout as PaneSplit).axis, SplitAxis.column);
      await chord(tester, [cmd, shift], LogicalKeyboardKey.keyD); // unbound
      expect(w.container.read(terminalTabsProvider).selected!.paneCount, 2);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a reload applies new chords at once (criterion 2)',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      w.fs.write(testConfigPaths().shellx, 'keybind = super+k=new_tab\n');
      await chord(tester, [
        cmd,
        shift,
      ], LogicalKeyboardKey.comma); // reload_config
      final before = w.container.read(terminalTabsProvider).tabs.length;
      await chord(tester, [cmd], LogicalKeyboardKey.keyK);
      expect(w.container.read(terminalTabsProvider).tabs.length, before + 1);
      expect(w.container.read(shellxConfigProvider).lastLoad!.manual, isTrue);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'AltGr+Q types while Ctrl+Alt+Q is bound (D26)',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'keybind = ctrl+alt+q=new_tab\n',
      );
      final tabs = w.container.read(terminalTabsProvider).tabs.length;
      await chord(tester, [
        ctrl,
        LogicalKeyboardKey.altRight,
      ], LogicalKeyboardKey.keyQ);
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs);
      await chord(tester, [
        ctrl,
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.keyQ);
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'text:, ignore and run_command reach the focused terminal (D31, D35)',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: r'''
keybind = ctrl+g=text:ls\n
keybind = ctrl+b=ignore
command = Lint = npm run lint
keybind = super+l=run_command:Lint
''',
      );
      final id = w.container.read(terminalTabsProvider).selected!.focused.id;
      final writes = w.local.views[id]!.writes;
      await chord(tester, [ctrl], LogicalKeyboardKey.keyG);
      expect(writes.join(), 'ls\n');
      writes.clear();
      await chord(tester, [ctrl], LogicalKeyboardKey.keyB);
      expect(writes, isEmpty);
      await chord(tester, [cmd], LogicalKeyboardKey.keyL);
      expect(writes.join(), 'npm run lint\r');
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    '⌘⌥, opens the ShellX file (A11 D10; it was ⌘, in A9 D37)',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final opener = RecordingOpener();
      final w = await pumpConfiguredWorkspace(
        tester,
        extra: [configFileOpenerProvider.overrideWithValue(opener)],
      );
      await chord(tester, [cmd, alt], LogicalKeyboardKey.comma);
      expect(opener.opened, [testConfigPaths().shellx]);
      // ⌘, alone is Settings now and opens no file.
      await chord(tester, [cmd], LogicalKeyboardKey.comma);
      expect(opener.opened, [testConfigPaths().shellx]);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'no config: the A1-A6 shortcuts are unchanged',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      expect(newTabShortcutLabel(), '⌘T');
      await chord(tester, [cmd], LogicalKeyboardKey.keyD);
      expect(w.container.read(terminalTabsProvider).selected!.paneCount, 2);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'AltGr yields for every Alt chord, whatever its intent (D26)',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config:
            'keybind = ctrl+alt+k=new_split:right\nkeybind = ctrl+alt+j=text:J\nkeybind = ctrl+alt+l=ignore\n',
      );
      final id = w.container.read(terminalTabsProvider).selected!.focused.id;
      final writes = w.local.views[id]!.writes;
      await chord(tester, [
        ctrl,
        LogicalKeyboardKey.altRight,
      ], LogicalKeyboardKey.keyK);
      expect(w.container.read(terminalTabsProvider).selected!.isSplit, isFalse);
      await chord(tester, [
        ctrl,
        LogicalKeyboardKey.altRight,
      ], LogicalKeyboardKey.keyJ);
      expect(writes.join(), isNot(contains('J')));
      await chord(tester, [
        ctrl,
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.keyJ);
      expect(writes.join(), 'J');
      await chord(tester, [
        ctrl,
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.keyK);
      expect(w.container.read(terminalTabsProvider).selected!.isSplit, isTrue);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a label on screen follows a reload (D29)',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      String tip() => tester
          .widget<Tooltip>(
            find.descendant(
              of: find.byKey(const Key('sidebar.newTab')),
              matching: find.byType(Tooltip),
            ),
          )
          .richMessage!
          .toPlainText();
      expect(tip(), contains('⌘T'));
      w.fs.write(testConfigPaths().shellx, 'keybind = super+shift+k=new_tab\n');
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(tip(), contains('⌘⇧K')); // the user's own chord leads (D29)
      expect(tip(), isNot(contains('⌘T')));
      w.fs.write(testConfigPaths().shellx, '# nothing\n');
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(tip(), contains('⌘T')); // back to the default
      w.fs.write(testConfigPaths().shellx, 'keybind = super+t=unbind\n');
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(tip(), 'New tab'); // unbound: no hint, no stray spaces
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'the empty state shows no caption for an unbound new tab',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'keybind = super+t=unbind\n',
      );
      w.container
          .read(terminalTabsProvider.notifier)
          .close(w.container.read(terminalTabsProvider).selectedId!);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pane.empty')), findsOneWidget);
      expect(find.text('⌘T'), findsNothing);
      w.fs.write(testConfigPaths().shellx, 'keybind = super+t=new_tab\n');
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(find.text('⌘T'), findsOneWidget);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'close_tab closes every pane of the tab',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'keybind = super+shift+w=close_tab\n',
      );
      await chord(tester, [cmd], LogicalKeyboardKey.keyD); // split
      expect(w.container.read(terminalTabsProvider).selected!.paneCount, 2);
      final page = tester.state<TerminalWorkspacePageState>(
        find.byType(TerminalWorkspacePage),
      );
      // The palette exists since Task 11: the intent opens it.
      expect(page.invokeIntent(const CommandPaletteIntent()), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      page.closePanel();
      await tester.pumpAndSettle();
      // The problems panel exists since Task 10: the intent opens it.
      expect(page.invokeIntent(const ShowConfigProblemsIntent()), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(ConfigProblemsPanel), findsOneWidget);
      page.closePanel();
      await tester.pumpAndSettle();
      await chord(tester, [cmd, shift], LogicalKeyboardKey.keyW);
      expect(w.container.read(terminalTabsProvider).tabs, isEmpty);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a right Alt on its own is not AltGr: the chord runs (Task 8 ruling)',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'keybind = alt+t=new_tab\nkeybind = ctrl+shift+alt+k=new_tab\n',
      );
      final tabs = w.container.read(terminalTabsProvider).tabs.length;
      await chord(tester, [
        LogicalKeyboardKey.altRight,
      ], LogicalKeyboardKey.keyT);
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
      // Ctrl + right Alt is AltGr: even a Ctrl+Shift+Alt chord yields.
      await chord(tester, [
        ctrl,
        shift,
        LogicalKeyboardKey.altRight,
      ], LogicalKeyboardKey.keyK);
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
      await chord(tester, [
        ctrl,
        shift,
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.keyK);
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 2);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'macOS has no AltGr: a right Alt chord runs',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        config: 'keybind = ctrl+alt+q=new_tab\n',
      );
      final tabs = w.container.read(terminalTabsProvider).tabs.length;
      await chord(tester, [
        ctrl,
        LogicalKeyboardKey.altRight,
      ], LogicalKeyboardKey.keyQ);
      expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'the pane header, the bell and the panel hint follow a reload (D29)',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      await chord(tester, [cmd], LogicalKeyboardKey.keyD); // split
      String tips() => tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message ?? t.richMessage?.toPlainText() ?? '')
          .join('|');
      expect(tips(), isNot(contains('⌘⇧J')));
      expect(tips(), isNot(contains('⌘⇧Q')));
      w.fs.write(
        testConfigPaths().shellx,
        'keybind = super+shift+j=toggle_notifications\n'
        'keybind = super+shift+q=close_surface\n'
        'keybind = super+shift+u=jump_to_unread\n',
      );
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(tips(), contains('⌘⇧J')); // the bell
      expect(tips(), contains('⌘⇧Q')); // the pane header's ×
      // The panel's footer hint shows once there is something to read.
      final id = w.container
          .read(terminalTabsProvider)
          .tabs
          .first
          .paneOrder
          .first;
      w.local.notice(id, SessionNoticeKind.message, title: 'Done', body: 'ok');
      await tester.pump();
      await tester.tap(find.byKey(const Key('sidebar.bell')));
      await tester.pumpAndSettle();
      expect(find.textContaining('⌘⇧U'), findsOneWidget);
      w.fs.write(testConfigPaths().shellx, 'keybind = super+shift+u=unbind\n');
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(find.textContaining('⌘⇧U'), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'the focus stays in the terminal across a reload',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(tester);
      final page = tester.state<TerminalWorkspacePageState>(
        find.byType(TerminalWorkspacePage),
      );
      expect(page.terminalFocus.hasFocus, isTrue);
      w.fs.write(testConfigPaths().shellx, 'keybind = super+k=new_tab\n');
      await w.container.read(shellxConfigProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(page.terminalFocus.hasFocus, isTrue);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a failed open shows the notice',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final w = await pumpConfiguredWorkspace(
        tester,
        extra: [
          configFileOpenerProvider.overrideWithValue(
            RecordingOpener(succeed: false),
          ),
        ],
      );
      await chord(tester, [cmd, alt], LogicalKeyboardKey.comma);
      expect(
        w.container.read(terminalTabsProvider).notice,
        isA<ConfigOpenFailedNotice>(),
      );
      await disposeWorkspace(tester, w.container);
    },
  );
}
