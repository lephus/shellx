import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/config_workspace.dart';

/// With [gate] the clipboard answers only once the gate completes (the
/// time the platform takes to read it).
void mockClipboard(WidgetTester t, String text, {Completer<void>? gate}) {
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method != 'Clipboard.getData') return null;
      await gate?.future;
      return <String, Object?>{'text': text};
    },
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

Future<void> pasteChord(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyV);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pump();
}

void main() {
  testWidgets(
    'a small paste is written at once, whole',
    (t) async {
      final w = await pumpConfiguredWorkspace(t);
      mockClipboard(t, 'echo hi\n');
      final id = w.container.read(terminalTabsProvider).selected!.focusedPaneId;
      await pasteChord(t);
      await t.pump();
      expect(w.local.views[id]!.writes.join(), 'echo hi\r');
      await disposeWorkspace(t, w.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    '800 KB arrives whole, in pieces, bracketed once',
    (t) async {
      final w = await pumpConfiguredWorkspace(t);
      final tab = w.container.read(terminalTabsProvider).selected!;
      tab.terminal.write('\x1b[?2004h'); // the program asks for bracketed paste
      final text = 'x' * 800000;
      mockClipboard(t, text);
      await pasteChord(t);
      await t.pump(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      final writes = w.local.views[tab.focusedPaneId]!.writes;
      expect(writes.first, '\x1b[200~');
      expect(writes.last, '\x1b[201~');
      expect(writes.sublist(1, writes.length - 1).join(), text);
      await disposeWorkspace(t, w.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'over 1 MiB asks first; No sends nothing',
    (t) async {
      final w = await pumpConfiguredWorkspace(t);
      final tab = w.container.read(terminalTabsProvider).selected!;
      mockClipboard(t, 'y' * (1024 * 1024 + 10));
      await pasteChord(t);
      await t.pump();
      final ask = w.container.read(windowRouterProvider).confirm!;
      expect(ask.title, 'Paste 1.0 MB?');
      ask.complete(false);
      await t.pump(const Duration(seconds: 1));
      expect(w.local.views[tab.focusedPaneId]!.writes, isEmpty);
      await disposeWorkspace(t, w.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'over 16 MiB is refused with a toast',
    (t) async {
      final w = await pumpConfiguredWorkspace(t);
      final tab = w.container.read(terminalTabsProvider).selected!;
      mockClipboard(t, 'z' * (16 * 1024 * 1024 + 1));
      await pasteChord(t);
      await t.pump();
      expect(
        w.container.read(terminalTabsProvider).notice,
        isA<PasteTooLargeNotice>(),
      );
      expect(w.local.views[tab.focusedPaneId]!.writes, isEmpty);
      await t.pump(const Duration(seconds: 7));
      await disposeWorkspace(t, w.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'the text goes to the pane focused when the key was pressed',
    (t) async {
      final w = await pumpConfiguredWorkspace(t);
      final tabs = w.container.read(terminalTabsProvider.notifier);
      await tabs.split(SplitAxis.row); // pane 101 focused, pane 100 not
      await t.pump();
      final first = w.container.read(terminalTabsProvider).selected!;
      final target = first.focusedPaneId;
      final other = first.paneOrder.firstWhere((id) => id != target);
      final gate = Completer<void>();
      mockClipboard(t, 'to the first', gate: gate);
      await pasteChord(t);
      tabs.focusPane(other); // focus moves while the clipboard is read
      await t.pump();
      gate.complete();
      await t.pump();
      await t.pump();
      expect(w.local.views[target]!.writes.join(), 'to the first');
      expect(w.local.views[other]!.writes, isEmpty);
      await disposeWorkspace(t, w.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a pane that closes mid-paste stops it and sends nothing more',
    (t) async {
      final w = await pumpConfiguredWorkspace(t);
      final tab = w.container.read(terminalTabsProvider).selected!;
      mockClipboard(t, 'k' * 400000);
      await pasteChord(t);
      await t.pump(const Duration(milliseconds: 20));
      final view = w.local.views[tab.focusedPaneId]!;
      w.container.read(terminalTabsProvider.notifier).close(tab.id);
      await t.pump();
      final seen = view.writes.length;
      await t.pump(const Duration(seconds: 3));
      expect(view.writes.length, seen);
      await disposeWorkspace(t, w.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
