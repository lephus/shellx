import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/clipboard_media.dart';
import 'package:shellx_desktop/src/terminal/paste_image_store.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/config_workspace.dart';

final class FakeMedia implements ClipboardMedia {
  List<String> fileList = const [];
  Uint8List? imageBytes;
  @override
  Future<List<String>> files() async => fileList;
  @override
  Future<Uint8List?> image() async => imageBytes;
}

final class FakeImageStore extends PasteImageStore {
  FakeImageStore() : super(Directory.systemTemp);
  final saved = <Uint8List>[];
  Object? error;
  @override
  Future<String> save(Uint8List bytes) async {
    if (error != null) throw error!;
    saved.add(bytes);
    return '/tmp/shellx-paste/paste-1.png';
  }
}

void mockClipboard(WidgetTester t, String? text) {
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData'
        ? (text == null ? null : <String, Object?>{'text': text})
        : null,
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
  await t.pump();
}

DropDoneDetails dropped(List<String> paths) => DropDoneDetails(
  files: [for (final p in paths) DropItemFile(p)],
  localPosition: Offset.zero,
  globalPosition: Offset.zero,
);

DropTarget targetOf(WidgetTester t, {int index = 0}) =>
    t.widgetList<DropTarget>(find.byType(DropTarget)).elementAt(index);

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets(
    'files dropped on the pane arrive escaped, with a space, no Enter',
    (t) async {
      final w = await pumpConfiguredWorkspace(t);
      final tab = w.container.read(terminalTabsProvider).selected!;
      targetOf(t).onDragDone!(
        dropped(['/Users/me/My Docs/a.png', '/Users/me/Tệp ảnh.txt']),
      );
      await t.pump();
      await t.pump();
      final writes = w.local.views[tab.focusedPaneId]!.writes.join();
      expect(writes, r'/Users/me/My\ Docs/a.png /Users/me/Tệp\ ảnh.txt ');
      expect(writes, isNot(contains('\r')));
      await disposeWorkspace(t, w.container);
    },
    variant: mac,
  );

  testWidgets('a program with bracketed paste gets the paths bracketed', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    tab.terminal.write('\x1b[?2004h');
    targetOf(t).onDragDone!(dropped(['/a b']));
    await t.pump();
    await t.pump();
    expect(
      w.local.views[tab.focusedPaneId]!.writes.join(),
      '\x1b[200~/a\\ b \x1b[201~',
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a name with a line break refuses the whole drop with a toast', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    final tab = w.container.read(terminalTabsProvider).selected!;
    targetOf(t).onDragDone!(dropped(['/ok.txt', '/bad\nname.txt']));
    await t.pump();
    await t.pump();
    expect(w.local.views[tab.focusedPaneId]!.writes, isEmpty);
    expect(
      (w.container.read(terminalTabsProvider).notice as InputNotice).kind,
      InputNoticeKind.dropRefused,
    );
    await t.pump(const Duration(seconds: 7));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('hover shows the hint; leaving, a drop or losing the window '
      'removes it', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    expect(find.byKey(const Key('drop.hint')), findsNothing);
    final details = DropEventDetails(
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    );
    targetOf(t).onDragEntered!(details);
    await t.pump();
    expect(find.byKey(const Key('drop.hint')), findsOneWidget);
    expect(find.text('Drop to insert the path'), findsOneWidget);
    targetOf(t).onDragExited!(details);
    await t.pump();
    expect(find.byKey(const Key('drop.hint')), findsNothing);
    targetOf(t).onDragEntered!(details);
    await t.pump();
    w.container.read(windowFocusProvider.notifier).set(true);
    w.container.read(windowFocusProvider.notifier).set(false);
    await t.pump();
    expect(find.byKey(const Key('drop.hint')), findsNothing);
    targetOf(t).onDragEntered!(details);
    await t.pump();
    targetOf(t).onDragDone!(dropped(['/a']));
    await t.pump();
    expect(find.byKey(const Key('drop.hint')), findsNothing);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('no drops while a dialog is open', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    expect(targetOf(t).enable, isTrue);
    unawaited(
      w.container
          .read(windowRouterProvider.notifier)
          .confirm(ConfirmRequest(title: 't', body: 'b', confirmLabel: 'ok')),
    );
    await t.pump();
    expect(targetOf(t).enable, isFalse);
    w.container.read(windowRouterProvider).confirm!.complete(false);
    await t.pump();
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a server pane refuses: a different hint, a toast, no text', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    final ssh = SessionRemote(
      launch: SshLaunch(SshTarget.parse('devbox')!),
      connected: true,
    );
    w.local.add(w.local.summary(7, origin: SessionOrigin.desktop, remote: ssh));
    await t.pump();
    w.container.read(terminalTabsProvider.notifier).focusPane(7);
    await t.pump();
    await t.pump();
    final index = t.widgetList<DropTarget>(find.byType(DropTarget)).length - 1;
    final details = DropEventDetails(
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    );
    targetOf(t, index: index).onDragEntered!(details);
    await t.pump();
    expect(
      find.text('Files can’t be dropped into an SSH session'),
      findsOneWidget,
    );
    targetOf(t, index: index).onDragDone!(dropped(['/a']));
    await t.pump();
    await t.pump();
    expect(w.local.views[7]!.writes, isEmpty);
    expect(
      (w.container.read(terminalTabsProvider).notice as InputNotice).kind,
      InputNoticeKind.dropSsh,
    );
    await t.pump(const Duration(seconds: 7));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('nothing of a dropped name or an image path is logged', (
    t,
  ) async {
    final logs = <String>[];
    final old = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    final w = await pumpConfiguredWorkspace(t);
    targetOf(t).onDragDone!(dropped(['/Users/me/Secret Plan.txt']));
    targetOf(t).onDragDone!(dropped(['/bad\nSecret Plan']));
    await t.pump();
    await t.pump();
    debugPrint = old;
    expect(logs.join(), isNot(contains('Secret')));
    await t.pump(const Duration(seconds: 7));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  group('the paste key', () {
    testWidgets('files on the clipboard win over their name as text', (
      t,
    ) async {
      final media = FakeMedia()..fileList = ['/Users/me/a b.png'];
      final w = await pumpConfiguredWorkspace(t, clipboard: media);
      mockClipboard(t, 'a b.png');
      final tab = w.container.read(terminalTabsProvider).selected!;
      await pasteChord(t);
      expect(
        w.local.views[tab.focusedPaneId]!.writes.join(),
        r'/Users/me/a\ b.png ',
      );
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('text wins over an image', (t) async {
      final media = FakeMedia()..imageBytes = Uint8List.fromList([0x89, 0x50]);
      final store = FakeImageStore();
      final w = await pumpConfiguredWorkspace(
        t,
        clipboard: media,
        extra: [pasteImageStoreProvider.overrideWithValue(store)],
      );
      mockClipboard(t, 'hello');
      final tab = w.container.read(terminalTabsProvider).selected!;
      await pasteChord(t);
      expect(w.local.views[tab.focusedPaneId]!.writes.join(), 'hello');
      expect(store.saved, isEmpty);
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('an image alone becomes a temp file and its path', (t) async {
      final media = FakeMedia()..imageBytes = Uint8List.fromList([0x89, 0x50]);
      final store = FakeImageStore();
      final w = await pumpConfiguredWorkspace(
        t,
        clipboard: media,
        extra: [pasteImageStoreProvider.overrideWithValue(store)],
      );
      mockClipboard(t, null);
      final tab = w.container.read(terminalTabsProvider).selected!;
      await pasteChord(t);
      expect(store.saved, hasLength(1));
      expect(
        w.local.views[tab.focusedPaneId]!.writes.join(),
        '/tmp/shellx-paste/paste-1.png ',
      );
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('an image over 20 MB, or an unreadable one, is a toast', (
      t,
    ) async {
      final media = FakeMedia()..imageBytes = Uint8List.fromList([0x89, 0x50]);
      final store = FakeImageStore()..error = const PasteImageTooLarge();
      final w = await pumpConfiguredWorkspace(
        t,
        clipboard: media,
        extra: [pasteImageStoreProvider.overrideWithValue(store)],
      );
      mockClipboard(t, null);
      await pasteChord(t);
      InputNoticeKind kind() =>
          (w.container.read(terminalTabsProvider).notice as InputNotice).kind;
      expect(kind(), InputNoticeKind.imageTooLarge);
      store.error = const FileSystemException('disk full');
      await pasteChord(t);
      expect(kind(), InputNoticeKind.imageFailed);
      await t.pump(const Duration(seconds: 7));
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('an image into a server pane is refused and nothing is saved', (
      t,
    ) async {
      final media = FakeMedia()..imageBytes = Uint8List.fromList([0x89, 0x50]);
      final store = FakeImageStore();
      final w = await pumpConfiguredWorkspace(
        t,
        clipboard: media,
        extra: [pasteImageStoreProvider.overrideWithValue(store)],
      );
      final ssh = SessionRemote(
        launch: SshLaunch(SshTarget.parse('devbox')!),
        connected: true,
      );
      w.local.add(
        w.local.summary(7, origin: SessionOrigin.desktop, remote: ssh),
      );
      await t.pump();
      w.container.read(terminalTabsProvider.notifier).focusPane(7);
      await t.pump();
      mockClipboard(t, null);
      await pasteChord(t);
      expect(store.saved, isEmpty);
      expect(
        (w.container.read(terminalTabsProvider).notice as InputNotice).kind,
        InputNoticeKind.imageSsh,
      );
      await t.pump(const Duration(seconds: 7));
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('text into a server pane still pastes', (t) async {
      final w = await pumpConfiguredWorkspace(t);
      final ssh = SessionRemote(
        launch: SshLaunch(SshTarget.parse('devbox')!),
        connected: true,
      );
      w.local.add(
        w.local.summary(7, origin: SessionOrigin.desktop, remote: ssh),
      );
      await t.pump();
      w.container.read(terminalTabsProvider.notifier).focusPane(7);
      await t.pump();
      mockClipboard(t, 'ls');
      await pasteChord(t);
      expect(w.local.views[7]!.writes.join(), 'ls');
      await disposeWorkspace(t, w.container);
    }, variant: mac);
  });
}
