import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/editor_links.dart';
import 'package:shellx_desktop/src/terminal/link_resolver.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/link_layer.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';
import 'package:xterm/xterm.dart';

import '../support/config_workspace.dart';
import '../support/fakes.dart';

/// The global position of the middle of cell ([col], [row]) of the view.
Offset cellCentre(WidgetTester t, int col, int row) {
  final state = t.state<TerminalViewState>(find.byType(TerminalView));
  final render = state.renderTerminal;
  final local = render.getOffset(CellOffset(col, row));
  return t.getTopLeft(find.byType(TerminalView)) +
      local +
      Offset(render.cellSize.width / 2, render.cellSize.height / 2);
}

RecordingUrlOpener opener(dynamic w) =>
    w.container.read(desktopServicesProvider).urlOpener as RecordingUrlOpener;

/// A mouse click (the default `tapAt` is a touch).
Future<void> click(WidgetTester t, Offset at) =>
    t.tapAt(at, kind: PointerDeviceKind.mouse);

Future<TestGesture> hover(WidgetTester t, Offset at) async {
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: const Offset(1, 1));
  addTearDown(g.removePointer);
  await g.moveTo(at);
  await t.pump();
  return g;
}

/// Sees only the app bundles in [installed] (never the real disk).
EditorDetector editors(Set<String> installed) => EditorDetector(
  windows: false,
  env: const {},
  home: '/Users/me',
  exists: (path) async => installed.contains(path),
);

/// `/work/notes.txt` is a file, `/work/src` a folder, nothing else exists.
LinkResolver workResolver() => LinkResolver(
  home: '/Users/me',
  windows: false,
  typeOf: (path) async => switch (path) {
    '/work/notes.txt' => FileSystemEntityType.file,
    '/work/src' => FileSystemEntityType.directory,
    _ => FileSystemEntityType.notFound,
  },
);

/// ⌘-clicks cell ([col], 0) of a pane showing [text], with [config] loaded
/// and [installed] app bundles.
Future<dynamic> cmdClickPath(
  WidgetTester t, {
  required String text,
  required int col,
  String config = '',
  Set<String> installed = const {'/Applications/Cursor.app'},
  bool fail = false,
}) async {
  final w = await pumpConfiguredWorkspace(
    t,
    config: config,
    extra: [
      linkResolverProvider.overrideWithValue(workResolver()),
      editorDetectorProvider.overrideWithValue(editors(installed)),
    ],
  );
  final tab = w.container.read(terminalTabsProvider).selected!;
  tab.terminal.write(text);
  await t.pump();
  opener(w).fail = fail;
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await click(t, cellCentre(t, col, 0));
  await t.pump(const Duration(milliseconds: 400));
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  return w;
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  group('link-editor: ⌘-click a file path', () {
    testWidgets('auto: the first installed editor opens it at line:col', (
      t,
    ) async {
      final w = await cmdClickPath(t, text: '/work/notes.txt:12:3 x', col: 3);
      expect(opener(w).edited.single, (
        EditorApp.cursor,
        '/work/notes.txt',
        12,
        3,
      ));
      expect(opener(w).revealed, isEmpty);
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('auto prefers Cursor, then VS Code, then Zed', (t) async {
      final w = await cmdClickPath(
        t,
        text: '/work/notes.txt:4',
        col: 3,
        installed: const {
          '/Applications/Zed.app',
          '/Applications/Visual Studio Code.app',
        },
      );
      expect(opener(w).edited.single, (
        EditorApp.vscode,
        '/work/notes.txt',
        4,
        null,
      ));
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('auto with no editor installed reveals, as before', (t) async {
      final w = await cmdClickPath(
        t,
        text: '/work/notes.txt:4',
        col: 3,
        installed: const {},
      );
      expect(opener(w).edited, isEmpty);
      expect(opener(w).revealed.single, ('/work/notes.txt', false));
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('finder: always reveals, whatever is installed', (t) async {
      final w = await cmdClickPath(
        t,
        text: '/work/notes.txt:4',
        col: 3,
        config: 'link-editor = finder\n',
      );
      expect(opener(w).edited, isEmpty);
      expect(opener(w).revealed.single, ('/work/notes.txt', false));
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('a named editor is used even when not found on disk', (
      t,
    ) async {
      final w = await cmdClickPath(
        t,
        text: '/work/notes.txt',
        col: 3,
        config: 'link-editor = zed\n',
        installed: const {},
      );
      expect(opener(w).edited.single, (
        EditorApp.zed,
        '/work/notes.txt',
        null,
        null,
      ));
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('a folder is still revealed, never sent to an editor', (
      t,
    ) async {
      final w = await cmdClickPath(
        t,
        text: '/work/src',
        col: 3,
        config: 'link-editor = cursor\n',
      );
      expect(opener(w).edited, isEmpty);
      expect(opener(w).revealed.single, ('/work/src', true));
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('a missing file opens nothing', (t) async {
      final w = await cmdClickPath(t, text: '/work/gone.txt:3', col: 3);
      expect(opener(w).edited, isEmpty);
      expect(opener(w).revealed, isEmpty);
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('an editor that fails to open is the usual toast', (t) async {
      final w = await cmdClickPath(
        t,
        text: '/work/notes.txt:1',
        col: 3,
        fail: true,
      );
      expect(
        w.container.read(terminalTabsProvider).notice,
        isA<LinkOpenFailedNotice>(),
      );
      await t.pump(const Duration(seconds: 7));
      await disposeWorkspace(t, w.container);
    }, variant: mac);
  });

  testWidgets('hover with ⌘ underlines a URL; without it nothing', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    tab.terminal.write('visit https://example.com/a?b=1.');
    await t.pump();
    await hover(t, cellCentre(t, 10, 0));
    expect(find.byKey(const Key('link.underline')), findsNothing);
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('link.underline')), findsOneWidget);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('link.underline')), findsNothing);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('⌘-click opens the URL without its full stop; a plain click '
      'does not', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    tab.terminal.write('visit https://example.com/a?b=1.');
    await t.pump();
    final at = cellCentre(t, 10, 0);
    await click(t, at);
    await t.pump(const Duration(milliseconds: 400));
    expect(opener(w).webLinks, isEmpty);
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await click(t, at);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump(const Duration(milliseconds: 400));
    expect(opener(w).webLinks.map((u) => u.toString()), [
      'https://example.com/a?b=1',
    ]);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('an OSC 8 link whose text differs asks first', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    tab.terminal.write(
      '\x1b]8;;https://example.com\x1b\\click here\x1b]8;;\x1b\\',
    );
    await t.pump();
    final at = cellCentre(t, 2, 0);
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await click(t, at);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump(const Duration(milliseconds: 400));
    final ask = w.container.read(windowRouterProvider).confirm!;
    expect(ask.title, 'Open this link?');
    expect(ask.body, contains('https://example.com'));
    expect(opener(w).webLinks, isEmpty);
    ask.complete(true);
    await t.pump(const Duration(milliseconds: 400));
    expect(opener(w).webLinks.single.toString(), 'https://example.com');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a failing browser is a toast, not an error', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    tab.terminal.write('https://example.com');
    await t.pump();
    opener(w).fail = true;
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await click(t, cellCentre(t, 3, 0));
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump(const Duration(milliseconds: 400));
    expect(
      w.container.read(terminalTabsProvider).notice,
      isA<LinkOpenFailedNotice>(),
    );
    await t.pump(const Duration(seconds: 7));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a failing open logs the error type, never the address', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    tab.terminal.write('https://example.com/SECRET-LINK-TEXT');
    await t.pump();
    opener(w).fail = true;
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await click(t, cellCentre(t, 3, 0));
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump(const Duration(milliseconds: 400));
    debugPrint =
        original; // the framework insists it is back before the test ends
    expect(lines.join(), contains('ProcessException'));
    expect(lines.join(), isNot(contains('SECRET')));
    await t.pump(const Duration(seconds: 7));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('an existing file is revealed; a missing one is no link', (
    t,
  ) async {
    final resolver = LinkResolver(
      home: '/Users/me',
      windows: false,
      typeOf: (path) async => path == '/work/notes.txt'
          ? FileSystemEntityType.file
          : FileSystemEntityType.notFound,
    );
    final w = await pumpConfiguredWorkspace(
      t,
      extra: [
        linkResolverProvider.overrideWithValue(resolver),
        // No editor installed: a file is shown in Finder, as before.
        editorDetectorProvider.overrideWithValue(editors(const {})),
      ],
    );
    final tab = w.container.read(terminalTabsProvider).selected!;
    tab.terminal.write('/work/notes.txt /work/missing.txt');
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await click(t, cellCentre(t, 20, 0)); // on /work/missing.txt
    await t.pump(const Duration(milliseconds: 400));
    expect(opener(w).revealed, isEmpty);
    await click(t, cellCentre(t, 3, 0)); // on /work/notes.txt
    await t.pump(const Duration(milliseconds: 400));
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(opener(w).revealed.single, ('/work/notes.txt', false));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a server pane links URLs but never paths', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final c = w.container;
    final ssh = SessionRemote(
      launch: SshLaunch(SshTarget.parse('devbox')!),
      connected: true,
    );
    w.local.add(w.local.summary(7, origin: SessionOrigin.desktop, remote: ssh));
    await t.pump();
    final tab = c.read(terminalTabsProvider).tabs.firstWhere((x) => x.id == 7);
    c.read(terminalTabsProvider.notifier).focusPane(7);
    await t.pump();
    tab.terminal.write('/etc/hosts https://example.com');
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await click(t, cellCentre(t, 3, 0));
    await t.pump(const Duration(milliseconds: 400));
    expect(opener(w).revealed, isEmpty);
    await click(t, cellCentre(t, 15, 0));
    await t.pump(const Duration(milliseconds: 400));
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(opener(w).webLinks, hasLength(1));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the menu on a link has Open link and Copy link address', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    tab.terminal.write('https://example.com/x');
    await t.pump();
    await t.tapAt(cellCentre(t, 4, 0), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu.openLink')), findsOneWidget);
    expect(find.text('Copy link address'), findsOneWidget);
    await t.tap(find.byKey(const Key('menu.openLink')));
    await t.pumpAndSettle();
    expect(opener(w).webLinks.single.toString(), 'https://example.com/x');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the menu away from a link has neither', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    tab.terminal.write('plain words');
    await t.pump();
    await t.tapAt(cellCentre(t, 2, 0), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu.openLink')), findsNothing);
    await t.tapAt(const Offset(2, 2));
    await t.pumpAndSettle();
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the question shows the real host on its own line, whatever '
      'the userinfo', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    final url = 'https://${'u' * 300}@evil.example/path';
    tab.terminal.write('\x1b]8;;$url\x1b\\paypal.com\x1b]8;;\x1b\\');
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await click(t, cellCentre(t, 2, 0));
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump(const Duration(milliseconds: 400));
    final ask = w.container.read(windowRouterProvider).confirm!;
    expect(ask.body.split('\n'), contains('evil.example'));
    expect(ask.body.length, lessThan(600));
    ask.complete(false);
    await t.pump(const Duration(milliseconds: 400));
    expect(opener(w).webLinks, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a click outside the grid opens nothing', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    final cols = tab.terminal.viewWidth;
    tab.terminal.write('https://example.com/${'a' * cols}');
    await t.pump();
    final render = t
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal;
    final box = t.getRect(find.byType(TerminalView));
    final gridRight =
        t.getTopLeft(find.byType(TerminalView)).dx +
        render.getOffset(CellOffset(cols, 0)).dx;
    expect(gridRight, lessThan(box.right - 0.5), reason: 'a strip is left');
    final at = Offset((gridRight + box.right) / 2, cellCentre(t, 0, 0).dy);
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await click(t, at);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump(const Duration(milliseconds: 400));
    expect(opener(w).webLinks, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);
}
