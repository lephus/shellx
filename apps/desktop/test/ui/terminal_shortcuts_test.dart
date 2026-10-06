import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_font_size.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

late FakeLocalSessions local;
late ProviderContainer container;

Future<void> pumpWorkspace(
  WidgetTester tester, {
  bool signedIn = true,
  Size size = const Size(1100, 720),
}) async {
  final h = TestHarness(settings: {'onboarding_done': true});
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
    ],
  );
  if (signedIn) await h.seedSignedIn();
  await container
      .read(agentControllerProvider.notifier)
      .bootstrap(watchForWake: false);
  container.read(windowRouterProvider.notifier).showTerminal();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: TerminalWorkspacePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Same teardown as terminal_workspace_test: bootstrap starts a periodic
/// update check, and testWidgets fails on pending timers before any
/// addTearDown callback could dispose the container.
void testShortcuts(
  String description,
  Future<void> Function(WidgetTester tester, bool mac) body,
) => testWidgets(
  description,
  variant: TargetPlatformVariant(const {
    TargetPlatform.macOS,
    TargetPlatform.windows,
  }),
  (tester) async {
    try {
      await body(tester, defaultTargetPlatform == TargetPlatform.macOS);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    }
  },
);

TerminalTabsState tabs() => container.read(terminalTabsProvider);

TerminalWorkspacePageState page(WidgetTester tester) => tester
    .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage));

/// ⌘ on macOS, Ctrl+Shift on Windows (spec criterion 2).
List<LogicalKeyboardKey> primary(bool mac) => mac
    ? [LogicalKeyboardKey.metaLeft]
    : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];

Future<void> chord(
  WidgetTester tester,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final m in modifiers) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final m in modifiers.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pumpAndSettle();
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// Captures Clipboard.setData and answers Clipboard.getData with [paste].
List<String> mockClipboard(WidgetTester tester, {String? paste}) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') {
        return paste == null ? null : {'text': paste};
      }
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

/// The intent [table] binds to [activator] (activators have no `==`).
Intent? lookup(
  Map<ShortcutActivator, Intent> table,
  SingleActivator activator,
) {
  for (final MapEntry(:key, :value) in table.entries) {
    if (key is SingleActivator &&
        key.trigger == activator.trigger &&
        key.control == activator.control &&
        key.shift == activator.shift &&
        key.alt == activator.alt &&
        key.meta == activator.meta) {
      return value;
    }
  }
  return null;
}

void main() {
  setUp(() => local = FakeLocalSessions());

  test('the tables follow spec criterion 2', () {
    final mac = desktopShortcuts(TargetPlatform.macOS);
    final win = desktopShortcuts(TargetPlatform.windows);
    expect(
      lookup(mac, const SingleActivator(LogicalKeyboardKey.keyT, meta: true)),
      isA<NewTabIntent>(),
    );
    expect(
      lookup(
        win,
        const SingleActivator(
          LogicalKeyboardKey.keyT,
          control: true,
          shift: true,
        ),
      ),
      isA<NewTabIntent>(),
    );
    expect(
      lookup(win, const SingleActivator(LogicalKeyboardKey.tab, control: true)),
      isA<NextTabIntent>(),
    );
    expect(
      lookup(mac, const SingleActivator(LogicalKeyboardKey.digit3, meta: true)),
      isA<SelectTabIntent>().having((i) => i.position, 'position', 3),
    );
    expect(
      lookup(
        win,
        const SingleActivator(
          LogicalKeyboardKey.digit9,
          control: true,
          alt: true,
        ),
      ),
      isA<SelectTabIntent>().having((i) => i.position, 'position', 9),
    );
    expect(
      lookup(
        mac,
        const SingleActivator(
          LogicalKeyboardKey.equal,
          meta: true,
          shift: true,
        ),
      ),
      isA<FontBiggerIntent>(),
    );
    // Plain Ctrl+letters always reach the shell.
    for (final letter in [
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyT,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyA,
    ]) {
      expect(lookup(win, SingleActivator(letter, control: true)), isNull);
      expect(lookup(mac, SingleActivator(letter, control: true)), isNull);
    }
  });

  testShortcuts('new tab, then close it, from inside the terminal', (
    tester,
    mac,
  ) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpWorkspace(tester);
    await chord(tester, primary(mac), LogicalKeyboardKey.keyT);
    expect(local.opens, hasLength(1));
    expect(tabs().tabs, hasLength(2));
    expect(tabs().selectedId, 100);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
    await chord(tester, primary(mac), LogicalKeyboardKey.keyW);
    expect(local.closed, [100]);
    expect(tabs().selectedId, 1);
    expect(local.views[1]!.writes, isEmpty);
  });

  testShortcuts('after the last tab closes (focus on "Open new tab") the '
      'window shortcuts still work', (tester, mac) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpWorkspace(tester);
    await chord(tester, primary(mac), LogicalKeyboardKey.keyW);
    expect(tabs().tabs, isEmpty);
    expect(page(tester).emptyFocus.hasFocus, isTrue);
    await chord(tester, primary(mac), LogicalKeyboardKey.keyT);
    expect(tabs().tabs, hasLength(1));
    expect(page(tester).terminalFocus.hasFocus, isTrue);
  });

  testShortcuts('with nothing focused the window shortcuts still work', (
    tester,
    mac,
  ) async {
    await pumpWorkspace(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await chord(tester, primary(mac), LogicalKeyboardKey.keyT);
    expect(tabs().tabs, hasLength(1));
    expect(page(tester).terminalFocus.hasFocus, isTrue);
  });

  testShortcuts('tab number and next/previous', (tester, mac) async {
    for (final id in [1, 2, 3]) {
      local.add(local.summary(id));
    }
    await pumpWorkspace(tester);
    final number = mac
        ? [LogicalKeyboardKey.metaLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.altLeft];
    await chord(tester, number, LogicalKeyboardKey.digit3);
    expect(tabs().selectedId, 3);
    // No 9th tab: nothing changes.
    await chord(tester, number, LogicalKeyboardKey.digit9);
    expect(tabs().selectedId, 3);
    await chord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.tab);
    expect(tabs().selectedId, 1);
    await chord(tester, [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.tab);
    expect(tabs().selectedId, 3);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
    // The shell never saw these chords.
    for (final id in [1, 2, 3]) {
      expect(local.views[id]!.writes, isEmpty);
    }
  });

  testShortcuts('AltGr+digit (Ctrl+right Alt) stays with the shell on '
      'Windows', (tester, mac) async {
    for (final id in [1, 2]) {
      local.add(local.summary(id));
    }
    await pumpWorkspace(tester);
    await chord(tester, [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altRight,
    ], LogicalKeyboardKey.digit2);
    // macOS has no Ctrl+Alt binding at all; Windows skips AltGr.
    expect(tabs().selectedId, 1);
  });

  testShortcuts('plain Ctrl+letters still reach the shell', (
    tester,
    mac,
  ) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpWorkspace(tester);
    await chord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.keyT);
    await chord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.keyC);
    expect(local.views[1]!.writes, ['\x14', '\x03']);
    expect(local.opens, isEmpty);
  });

  testShortcuts('font size bigger / smaller / reset', (tester, mac) async {
    local.add(local.summary(1));
    await pumpWorkspace(tester);
    final fontKeys = mac
        ? [LogicalKeyboardKey.metaLeft]
        : [LogicalKeyboardKey.controlLeft];
    await chord(tester, fontKeys, LogicalKeyboardKey.equal);
    expect(container.read(terminalFontSizeProvider), 14);
    // ⌘+ is ⌘⇧= on a US layout.
    await chord(tester, [
      ...fontKeys,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.equal);
    expect(container.read(terminalFontSizeProvider), 15);
    await chord(tester, fontKeys, LogicalKeyboardKey.minus);
    await chord(tester, fontKeys, LogicalKeyboardKey.minus);
    await chord(tester, fontKeys, LogicalKeyboardKey.minus);
    expect(container.read(terminalFontSizeProvider), 12);
    await chord(tester, fontKeys, LogicalKeyboardKey.digit0);
    expect(container.read(terminalFontSizeProvider), 13);
    expect(local.views[1]!.writes, isEmpty);
  });

  testShortcuts('paste goes to the shell cleaned', (tester, mac) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpWorkspace(tester);
    mockClipboard(tester, paste: 'echo hi\x1b[201~');
    await chord(tester, primary(mac), LogicalKeyboardKey.keyV);
    expect(local.views[1]!.writes, ['echo hi[201~']);
  });

  testShortcuts('copy takes the selection and clears it', (tester, mac) async {
    local.add(
      local.summary(1, origin: SessionOrigin.desktop),
      backlog: 'hello world',
    );
    await pumpWorkspace(tester);
    final copied = mockClipboard(tester);
    final tab = tabs().selected!;
    tab.selection.setSelection(
      tab.terminal.buffer.createAnchor(0, 0),
      tab.terminal.buffer.createAnchor(5, 0),
    );
    await chord(tester, primary(mac), LogicalKeyboardKey.keyC);
    expect(copied, ['hello']);
    expect(tab.selection.selection, isNull);
    expect(local.views[1]!.writes, isEmpty);
  });

  testShortcuts('copy without a selection copies nothing and leaves the '
      'key to the terminal', (tester, mac) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpWorkspace(tester);
    final copied = mockClipboard(tester);
    await chord(tester, primary(mac), LogicalKeyboardKey.keyC);
    expect(copied, isEmpty);
    // xterm has no sequence for ⌘C / Ctrl+Shift+C: nothing reaches the
    // shell, and no window action ran.
    expect(local.views[1]!.writes, isEmpty);
    expect(tabs().tabs, hasLength(1));
  });

  testShortcuts('close with nothing open hides the window (UI §2.7)', (
    tester,
    mac,
  ) async {
    await pumpWorkspace(tester);
    await chord(tester, primary(mac), LogicalKeyboardKey.keyW);
    expect(container.read(windowRouterProvider).visible, isFalse);
  });

  testShortcuts('F6 moves between the terminal and the sidebar; arrows, '
      'Home and End move the selection; Esc comes back', (tester, mac) async {
    for (final id in [1, 2, 3]) {
      local.add(local.summary(id));
    }
    await pumpWorkspace(tester);
    final p = page(tester);
    expect(p.terminalFocus.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.f6);
    expect(p.sidebarFocus.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(tabs().selectedId, 2);
    expect(p.sidebarFocus.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.end);
    expect(tabs().selectedId, 3);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(tabs().selectedId, 2);
    await key(tester, LogicalKeyboardKey.home);
    expect(tabs().selectedId, 1);
    expect(p.sidebarFocus.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.escape);
    expect(p.terminalFocus.hasFocus, isTrue);
    // Enter selects and hands the keyboard to the terminal too.
    await key(tester, LogicalKeyboardKey.f6);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.enter);
    expect(tabs().selectedId, 2);
    expect(p.terminalFocus.hasFocus, isTrue);
    for (final id in [1, 2, 3]) {
      expect(local.views[id]!.writes, isEmpty);
    }
  });

  testShortcuts('window shortcuts work from the sidebar', (tester, mac) async {
    for (final id in [1, 2]) {
      local.add(local.summary(id));
    }
    await pumpWorkspace(tester);
    await key(tester, LogicalKeyboardKey.f6);
    expect(page(tester).sidebarFocus.hasFocus, isTrue);
    await chord(
      tester,
      mac
          ? [LogicalKeyboardKey.metaLeft]
          : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.altLeft],
      LogicalKeyboardKey.digit2,
    );
    expect(tabs().selectedId, 2);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
  });

  testShortcuts('signed out, F6 / Shift+F6 cycle terminal → sidebar → strip', (
    tester,
    mac,
  ) async {
    local.add(local.summary(1));
    await pumpWorkspace(tester, signedIn: false);
    final p = page(tester);
    expect(find.byKey(const Key('pane.signedOutStrip')), findsOneWidget);
    expect(p.terminalFocus.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.f6);
    expect(p.sidebarFocus.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.f6);
    expect(p.stripFocus.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.f6);
    expect(p.terminalFocus.hasFocus, isTrue);
    await chord(tester, [LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.f6);
    expect(p.stripFocus.hasFocus, isTrue);
    await chord(tester, [LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.f6);
    expect(p.sidebarFocus.hasFocus, isTrue);
    // A window shortcut from the strip.
    await key(tester, LogicalKeyboardKey.f6);
    expect(p.stripFocus.hasFocus, isTrue);
    await chord(tester, primary(mac), LogicalKeyboardKey.keyT);
    expect(tabs().tabs, hasLength(2));
    expect(p.terminalFocus.hasFocus, isTrue);
  });

  testShortcuts('signed in, F6 skips the strip', (tester, mac) async {
    local.add(local.summary(1));
    await pumpWorkspace(tester);
    final p = page(tester);
    await key(tester, LogicalKeyboardKey.f6);
    await key(tester, LogicalKeyboardKey.f6);
    expect(p.terminalFocus.hasFocus, isTrue);
  });

  testShortcuts('the selected row scrolls into view, so Shift+F10 reaches it', (
    tester,
    mac,
  ) async {
    for (var id = 1; id <= 30; id++) {
      local.add(local.summary(id));
    }
    await pumpWorkspace(tester, size: const Size(800, 400));
    await key(tester, LogicalKeyboardKey.f6);
    await key(tester, LogicalKeyboardKey.end);
    expect(tabs().selectedId, 30);
    final list = tester.getRect(find.byType(ListView));
    final row = tester.getRect(find.byKey(const ValueKey('tab.30')));
    expect(list.top <= row.top && row.bottom <= list.bottom, isTrue);
    await chord(tester, [LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.f10);
    expect(find.byKey(const Key('menu.closeTab')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    await key(tester, LogicalKeyboardKey.home);
    final first = tester.getRect(find.byKey(const ValueKey('tab.1')));
    expect(list.top <= first.top && first.bottom <= list.bottom, isTrue);
    // Scrolled away with the wheel: Shift+F10 brings the row back first.
    final scroll = page(tester).sidebarScroll;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tab.1')), findsNothing);
    await chord(tester, [LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.f10);
    expect(find.byKey(const Key('menu.closeTab')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    expect(page(tester).sidebarFocus.hasFocus, isTrue);
    // ⌘9 / Ctrl+Alt+9 from the terminal reveals that row as well.
    await key(tester, LogicalKeyboardKey.escape);
    await chord(
      tester,
      mac
          ? [LogicalKeyboardKey.metaLeft]
          : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.altLeft],
      LogicalKeyboardKey.digit9,
    );
    expect(tabs().selectedId, 9);
    expect(find.byKey(const ValueKey('tab.9')), findsOneWidget);
  });
}
