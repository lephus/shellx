import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/command_palette.dart' show Keycaps;
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/config/shortcuts_sheet.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

const cmd = LogicalKeyboardKey.metaLeft;
const ctrl = LogicalKeyboardKey.controlLeft;
const alt = LogicalKeyboardKey.altLeft;

Future<void> press(
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

Finder row(String action) => find.byKey(ValueKey('shortcuts.row.$action'));

Finder addButton(String action) =>
    find.descendant(of: row(action), matching: find.text('Add shortcut'));

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<({dynamic w})> open(WidgetTester tester, {String config = ''}) async {
    final w = await pumpConfiguredWorkspace(tester, config: config);
    w.container
        .read(configUiRequestProvider.notifier)
        .request(ConfigUiRequest.shortcuts);
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutsSheet), findsOneWidget);
    return (w: w);
  }

  testWidgets(
    'record a chord: the file gets one managed line and it works (criterion 8)',
    variant: mac,
    (tester) async {
      final (:w) = await open(tester, config: '# keep me\n');
      await tester.tap(addButton('new_tab'));
      await tester.pumpAndSettle();
      expect(
        find.text('Press a key combination… (Esc to cancel)'),
        findsOneWidget,
      );
      await press(tester, [ctrl, alt], LogicalKeyboardKey.keyN);
      final text = w.fs.text(testConfigPaths().shellx);
      expect(text, startsWith('# keep me\n'));
      expect(text, contains('keybind = ctrl+alt+n=new_tab'));
      expect(
        w.container
            .read(shellxConfigProvider)
            .bindings
            .triggersOf(const KeyAction('new_tab')),
        hasLength(2),
      );
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('a taken chord asks; Replace moves it', variant: mac, (
    tester,
  ) async {
    final (:w) = await open(tester);
    await tester.tap(addButton('new_tab'));
    await tester.pumpAndSettle();
    await press(tester, [cmd], LogicalKeyboardKey.keyD);
    expect(find.text('⌘D is used by “Split right”.'), findsOneWidget);
    expect(w.fs.files.containsKey(testConfigPaths().shellx), isFalse);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(
      w.fs.text(testConfigPaths().shellx),
      contains('keybind = super+d=new_tab'),
    );
    expect(
      w.container
          .read(shellxConfigProvider)
          .bindings
          .labelOf(const KeyAction('new_split', 'right')),
      isNull,
    );
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('Cancel on a conflict writes nothing', variant: mac, (
    tester,
  ) async {
    final (:w) = await open(tester);
    await tester.tap(addButton('new_tab'));
    await tester.pumpAndSettle();
    await press(tester, [cmd], LogicalKeyboardKey.keyD);
    // The recorder's own Cancel and the conflict line's: take the line's.
    await tester.tap(
      find.descendant(of: row('new_tab'), matching: find.text('Cancel')).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('⌘D is used by “Split right”.'), findsNothing);
    expect(w.fs.files.containsKey(testConfigPaths().shellx), isFalse);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'Esc cancels recording; F6 and plain keys are refused in place',
    variant: mac,
    (tester) async {
      final (:w) = await open(tester);
      await tester.tap(addButton('new_tab'));
      await tester.pumpAndSettle();
      await press(tester, const [], LogicalKeyboardKey.f6);
      expect(
        find.text('F6 and Shift+F6 always move between regions'),
        findsOneWidget,
      );
      await press(tester, const [], LogicalKeyboardKey.keyA);
      expect(find.text('A is for typing — add Ctrl, Alt or ⌘'), findsOneWidget);
      await press(tester, const [], LogicalKeyboardKey.escape);
      expect(
        find.text('Press a key combination… (Esc to cancel)'),
        findsNothing,
      );
      expect(
        find.byType(ShortcutsSheet),
        findsOneWidget,
      ); // Esc only left recording
      expect(w.fs.files.containsKey(testConfigPaths().shellx), isFalse);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('system-reserved chords are refused in place', variant: mac, (
    tester,
  ) async {
    final (:w) = await open(tester);
    await tester.tap(addButton('new_tab'));
    await tester.pumpAndSettle();
    await press(tester, [cmd], LogicalKeyboardKey.keyQ);
    expect(
      find.text('Press a key combination… (Esc to cancel)'),
      findsOneWidget,
    );
    expect(w.fs.files.containsKey(testConfigPaths().shellx), isFalse);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('a held modifier shows while recording', variant: mac, (
    tester,
  ) async {
    final (:w) = await open(tester);
    await tester.tap(addButton('new_tab'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(cmd);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('⌘⇧…'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(cmd);
    await tester.pump();
    expect(
      find.text('Press a key combination… (Esc to cancel)'),
      findsOneWidget,
    );
    expect(w.fs.files.containsKey(testConfigPaths().shellx), isFalse);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'a D25 note is shown under the row for 4 s after recording',
    variant: mac,
    (tester) async {
      final (:w) = await open(tester);
      await tester.tap(addButton('new_tab'));
      await tester.pumpAndSettle();
      await press(tester, [ctrl], LogicalKeyboardKey.keyC);
      expect(
        w.fs.text(testConfigPaths().shellx),
        contains('keybind = ctrl+c=new_tab'),
      );
      expect(find.text('⌃C will no longer reach the shell'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('⌃C will no longer reach the shell'), findsNothing);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('remove a default and reset it', variant: mac, (tester) async {
    final semantics = tester.ensureSemantics();
    final (:w) = await open(tester);
    await tester.tap(
      find.descendant(
        of: row('new_tab'),
        matching: find.bySemanticsLabel('Remove ⌘T'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      w.fs.text(testConfigPaths().shellx),
      contains('keybind = super+t=unbind'),
    );
    expect(
      find.descendant(of: row('new_tab'), matching: find.text('Not set')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: row('new_tab'), matching: find.text('Reset')),
    );
    await tester.pumpAndSettle();
    expect(w.fs.text(testConfigPaths().shellx), isNot(contains('super+t')));
    expect(
      w.container
          .read(shellxConfigProvider)
          .bindings
          .labelOf(const KeyAction('new_tab')),
      '⌘T',
    );
    await disposeWorkspace(tester, w.container);
    semantics.dispose();
  });

  testWidgets(
    'only chords written outside the managed block are dashed (D19)',
    variant: mac,
    (tester) async {
      final (:w) = await open(tester, config: 'keybind = super+j=new_tab\n');
      bool? dashed(String label) => tester
          .widgetList<Keycaps>(
            find.descendant(of: row('new_tab'), matching: find.byType(Keycaps)),
          )
          .where((k) => k.label == label)
          .map((k) => k.dashed)
          .firstOrNull;
      expect(dashed('⌘J'), isTrue);
      expect(dashed('⌘T'), isFalse);
      await tester.tap(addButton('new_tab'));
      await tester.pumpAndSettle();
      await press(tester, [ctrl, alt], LogicalKeyboardKey.keyN);
      expect(dashed('⌃⌥N'), isFalse);
      expect(dashed('⌘J'), isTrue);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a save that fails shows the notice and the file stays as it was',
    variant: mac,
    (tester) async {
      final (:w) = await open(tester, config: 'font-size = 14\n');
      w.fs.replaceError = const FileSystemException('denied');
      await tester.tap(addButton('new_tab'));
      await tester.pumpAndSettle();
      await press(tester, [ctrl, alt], LogicalKeyboardKey.keyN);
      expect(
        w.container.read(terminalTabsProvider).notice,
        isA<ConfigWriteFailedNotice>().having(
          (n) => n.path,
          'path',
          testConfigPaths().shellx,
        ),
      );
      expect(
        find.text("Couldn't save the shortcut to ${testConfigPaths().shellx}"),
        findsOneWidget,
      );
      expect(w.fs.text(testConfigPaths().shellx), 'font-size = 14\n');
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'a file edited elsewhere meanwhile is kept and reloaded, not overwritten',
    variant: mac,
    (tester) async {
      final (:w) = await open(tester, config: 'font-size = 14\n');
      final path = testConfigPaths().shellx;
      w.fs.beforeReplace = (p) {
        w.fs.beforeReplace = null;
        w.fs.write(p, 'font-size = 18\n');
      };
      await tester.tap(addButton('new_tab'));
      await tester.pumpAndSettle();
      await press(tester, [ctrl, alt], LogicalKeyboardKey.keyN);
      expect(w.fs.text(path), 'font-size = 18\n');
      expect(
        w.container.read(terminalTabsProvider).notice,
        isA<ConfigWriteFailedNotice>(),
      );
      // The window followed the file on disk.
      expect(w.container.read(shellxConfigProvider).config.fontSize, 18);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets(
    'window shortcuts do not run under the sheet (UI-A9 §4.2)',
    variant: mac,
    (tester) async {
      final (:w) = await open(tester);
      final before = w.container.read(terminalTabsProvider).tabs.length;
      await press(tester, [
        cmd,
      ], LogicalKeyboardKey.keyT); // ⌘T would open a tab
      expect(w.container.read(terminalTabsProvider).tabs.length, before);
      expect(find.byType(ShortcutsSheet), findsOneWidget);
      await disposeWorkspace(tester, w.container);
    },
  );

  testWidgets('Esc closes the sheet', variant: mac, (tester) async {
    final (:w) = await open(tester);
    await press(tester, const [], LogicalKeyboardKey.escape);
    expect(find.byType(ShortcutsSheet), findsNothing);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets(
    'the watcher sees our own write: one more load, no problems toast, nothing lost',
    variant: mac,
    (tester) async {
      final (:w) = await open(
        tester,
        config: 'no-such-key = 1\nfont-size = 14\n',
      );
      final tabs = w.container.read(terminalTabsProvider.notifier);
      tabs.dismissNotice(); // the toast the first load raised
      await tester.pump();
      w.container
          .read(shellxConfigProvider.notifier)
          .startWatching(interval: const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(addButton('new_tab'));
      await tester.pumpAndSettle();
      await press(tester, [ctrl, alt], LogicalKeyboardKey.keyN);
      final generation = w.container.read(shellxConfigProvider).generation;
      // The poll notices the new stamp and loads again.
      await tester.pump(const Duration(seconds: 2));
      expect(
        w.container.read(shellxConfigProvider).generation,
        greaterThan(generation),
      );
      expect(w.container.read(terminalTabsProvider).notice, isNull);
      // The save is in the file and in effect.
      expect(
        w.fs.text(testConfigPaths().shellx),
        startsWith('no-such-key = 1\nfont-size = 14\n'),
      );
      expect(
        w.container
            .read(shellxConfigProvider)
            .bindings
            .triggersOf(const KeyAction('new_tab')),
        hasLength(2),
      );
      await disposeWorkspace(tester, w.container);
    },
  );
}
