import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/tools/tool_actions.dart';
import 'package:shellx_desktop/src/ui/tools/tool_dialogs.dart';

import '../../support/config_workspace.dart';
import '../../support/fake_local_sessions.dart';
import '../../support/fakes.dart';
import '../../support/tool_harness.dart';

void main() {
  late ToolRig rig;
  setUp(() => rig = ToolRig());

  /// The dialog alone; what Add does with it is the window's (Task 13).
  Future<ToolDraft?> Function() openDialog(
    WidgetTester t, {
    String ws = kDefaultWorkspaceId,
  }) {
    ToolDraft? result;
    var done = false;
    unawaited(
      showToolDialog(
        t.element(find.byType(TerminalWorkspacePage)),
        ws: ws,
      ).then((r) {
        result = r;
        done = true;
      }),
    );
    return () async {
      await t.pumpAndSettle();
      expect(done, isTrue);
      return result;
    };
  }

  Future<void> shown(WidgetTester t) async {
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tool.dialog')), findsOneWidget);
  }

  /// The terminal pane of tab [tab] listens on [port], in a `node` process.
  void listens(int tab, int port) {
    final local =
        rig.container.read(localSessionsProvider) as FakeLocalSessions;
    local.replace(local.summary(tab, ports: [port]));
    rig.probe.ports[100] = {port};
    rig.probe.table[100] = (parent: 1, name: 'node');
  }

  /// The window's tool commands over the rig's providers, and a context in
  /// the window to show dialogs from. With [opener], the commands are built
  /// in a scope of their own that swaps only the services: links open
  /// through [opener], not through the rig's recording one.
  Future<_Window> window(WidgetTester t, {UrlOpener? opener}) async {
    late WidgetRef ref;
    late BuildContext context;
    Widget probe = Consumer(
      builder: (c, r, _) {
        ref = r;
        context = c;
        return const SizedBox.shrink();
      },
    );
    if (opener != null) {
      probe = ProviderScope(
        overrides: [
          desktopServicesProvider.overrideWithValue(
            _servicesOpening(rig.harness, opener),
          ),
        ],
        child: probe,
      );
    }
    Overlay.of(
      t.element(find.byType(TerminalWorkspacePage)),
    ).insert(OverlayEntry(builder: (_) => probe));
    await t.pump();
    return (actions: ToolActions(ref), context: context);
  }

  /// A page's `alert` / `confirm` / `prompt` on the window. The closure
  /// gives what the page gets, once the test has answered the dialog.
  Future<Object?> Function() asks(WidgetTester t, BrowserJsDialog dialog) {
    Object? answer;
    var done = false;
    unawaited(
      showToolJsDialog(
        t.element(find.byType(TerminalWorkspacePage)),
        'Task board',
        dialog,
      ).then((r) {
        answer = r;
        done = true;
      }),
    );
    return () async {
      await t.pumpAndSettle();
      expect(done, isTrue);
      return answer;
    };
  }

  testWidgets('suggestions: a terminal\'s port named by its program; a pick '
      'fills the URL and the name (D12)', (t) async {
    await rig.pump(t);
    final local =
        rig.container.read(localSessionsProvider) as FakeLocalSessions;
    final session = rig.container.read(terminalTabsProvider).tabs.single.id;
    local.replace(local.summary(session, ports: [5173]));
    rig.probe.ports[100] = {5173};
    rig.probe.table[100] = (parent: 1, name: 'node');
    await t.pumpAndSettle();
    final closed = openDialog(t);
    await shown(t);
    expect(find.text('localhost:5173 · node'), findsOneWidget);
    await t.tap(find.byKey(const Key('tool.suggestion.5173')));
    await t.pump();
    expect(find.text('http://localhost:5173/'), findsOneWidget);
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    final draft = (await closed())!;
    expect(
      [draft.name, draft.url, draft.phone],
      ['node', 'http://localhost:5173/', false],
    );
    expect(draft.toString(), 'ToolDraft(…)', reason: 'D24: no name, no URL');
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('no port yet: the hint (D12)', (t) async {
    await rig.pump(t);
    openDialog(t);
    await shown(t);
    expect(find.byKey(const Key('tool.suggestions.none')), findsOneWidget);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('a bad URL says why after Add, and adds nothing (§4.2)', (
    t,
  ) async {
    await rig.pump(t);
    final closed = openDialog(t);
    await shown(t);
    await t.enterText(
      find.byKey(const Key('tool.dialog.url')),
      'javascript:alert(1)',
    );
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    await t.pump();
    expect(
      find.text('The URL must start with http:// or https://'),
      findsOneWidget,
    );
    await t.enterText(
      find.byKey(const Key('tool.dialog.url')),
      'http://me:pw@localhost:1',
    );
    await t.pump();
    expect(
      find.text("The URL can't contain a user name or password"),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('tool.dialog.cancel')));
    expect(await closed(), isNull);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('"Allow on phone" is off for a tool that is not local http '
      '(D15)', (t) async {
    await rig.pump(t);
    final closed = openDialog(t);
    await shown(t);
    await t.enterText(find.byKey(const Key('tool.dialog.url')), 'nas.lan:80');
    await t.pump();
    final box = t.widget<CheckboxListTile>(
      find.byKey(const Key('tool.dialog.phone')),
    );
    expect(box.onChanged, isNull);
    expect(
      find.text('Only http tools on this computer can open on a phone.'),
      findsOneWidget,
    );
    await t.enterText(
      find.byKey(const Key('tool.dialog.url')),
      'localhost:3000',
    );
    await t.pump();
    await t.tap(find.byKey(const Key('tool.dialog.phone')));
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    expect((await closed())!.phone, isTrue);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('a full project says so; Add is off (D2)', (t) async {
    await rig.pump(t);
    for (var i = 1; i <= kMaxToolsPerWorkspace; i++) {
      rig.add(kDefaultWorkspaceId, 'localhost:$i');
    }
    await t.pumpAndSettle();
    openDialog(t);
    await shown(t);
    expect(find.byKey(const Key('tool.dialog.full')), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('tool.dialog.save')))
          .onPressed,
      isNull,
    );
    await disposeWorkspace(t, rig.container);
  });

  group('Add tool: the phone note and the picked name (§4.2, D12, D15)', () {
    const note =
        'Through the relay, end-to-end encrypted. '
        'The phone can reach this URL only.';
    const refusal = 'Only http tools on this computer can open on a phone.';

    testWidgets('the note shows until a URL is typed that a phone may not '
        'open; the box is off without a URL', (t) async {
      await rig.pump(t);
      openDialog(t);
      await shown(t);
      CheckboxListTile box() => t.widget<CheckboxListTile>(
        find.byKey(const Key('tool.dialog.phone')),
      );
      expect(find.text(note), findsOneWidget);
      expect(find.text(refusal), findsNothing);
      expect(box().onChanged, isNull, reason: 'no URL yet');
      await t.enterText(
        find.byKey(const Key('tool.dialog.url')),
        'http://example.com',
      );
      await t.pump();
      expect(find.text(refusal), findsOneWidget);
      expect(find.text(note), findsNothing);
      expect(box().onChanged, isNull);
      await t.enterText(
        find.byKey(const Key('tool.dialog.url')),
        'localhost:5173',
      );
      await t.pump();
      expect(find.text(note), findsOneWidget);
      expect(find.text(refusal), findsNothing);
      expect(box().onChanged, isNotNull);
      await disposeWorkspace(t, rig.container);
    });

    testWidgets('a pick names the tool after the project folder of the '
        'workspace', (t) async {
      await rig.pump(t);
      final side = rig.container.read(sidebarWorkspacesProvider.notifier);
      final ws = side.createFor(name: 'Board');
      await side.openTabIn(ws);
      side.setRoot(ws, '/Users/me/projects/kanban');
      listens(
        rig.container.read(sidebarWorkspacesProvider).tabsOf(ws).single,
        5173,
      );
      await t.pumpAndSettle();
      final closed = openDialog(t, ws: ws);
      await shown(t);
      await t.tap(find.byKey(const Key('tool.suggestion.5173')));
      await t.pump();
      await t.tap(find.byKey(const Key('tool.dialog.save')));
      final draft = (await closed())!;
      expect(
        [draft.name, draft.url],
        ['kanban', 'http://localhost:5173/'],
        reason: 'the folder, not the process ("node")',
      );
      await disposeWorkspace(t, rig.container);
    });

    testWidgets('a pick keeps the name that was typed', (t) async {
      await rig.pump(t);
      listens(rig.container.read(terminalTabsProvider).tabs.single.id, 5173);
      await t.pumpAndSettle();
      final closed = openDialog(t);
      await shown(t);
      await t.enterText(find.byKey(const Key('tool.dialog.name')), 'My board');
      await t.tap(find.byKey(const Key('tool.suggestion.5173')));
      await t.pump();
      await t.tap(find.byKey(const Key('tool.dialog.save')));
      final draft = (await closed())!;
      expect([draft.name, draft.url], ['My board', 'http://localhost:5173/']);
      await disposeWorkspace(t, rig.container);
    });
  });

  // The commands and dialogs around the dialog, which the window's own tests
  // (the dock, the sidebar rows) do not reach.

  group('a page\'s JavaScript dialogs (§7, D9)', () {
    const alert = BrowserJsDialog(
      kind: BrowserJsDialogKind.alert,
      message: 'Saved',
    );
    const confirm = BrowserJsDialog(
      kind: BrowserJsDialogKind.confirm,
      message: 'Delete it?',
    );
    const prompt = BrowserJsDialog(
      kind: BrowserJsDialogKind.prompt,
      message: 'Name?',
      defaultText: 'Board',
    );

    testWidgets('the title names the tool, in both languages, so a page '
        'cannot pass for ShellX', (t) async {
      await rig.pump(t);
      for (final (locale, title) in [
        (const Locale('en'), 'Task board says'),
        (const Locale('vi'), 'Task board nhắn'),
      ]) {
        await t.pumpWidget(workspaceApp(rig.container, locale: locale));
        final answer = asks(t, alert);
        await t.pumpAndSettle();
        expect(find.text(title), findsOneWidget, reason: '$locale');
        expect(find.text('Saved'), findsOneWidget);
        await t.tap(find.byKey(const Key('tool.js.ok')));
        await answer();
      }
      await disposeWorkspace(t, rig.container);
    });

    testWidgets('alert, confirm and prompt answer as the page expects; '
        'Cancel is a no', (t) async {
      await rig.pump(t);
      Future<Object?> press(
        BrowserJsDialog dialog,
        String button, {
        String? type,
      }) async {
        final answer = asks(t, dialog);
        await t.pumpAndSettle();
        if (type != null) {
          await t.enterText(find.byKey(const Key('tool.js.text')), type);
        }
        await t.tap(find.byKey(Key(button)));
        return answer();
      }

      final alerted = asks(t, alert);
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('tool.js.cancel')),
        findsNothing,
        reason: 'an alert only says',
      );
      await t.tap(find.byKey(const Key('tool.js.ok')));
      expect(await alerted(), isNull);
      expect(await press(confirm, 'tool.js.ok'), isTrue);
      expect(await press(confirm, 'tool.js.cancel'), isFalse);
      expect(
        await press(prompt, 'tool.js.ok'),
        'Board',
        reason: 'the default text the page gave',
      );
      expect(await press(prompt, 'tool.js.ok', type: 'Kanban'), 'Kanban');
      expect(await press(prompt, 'tool.js.cancel', type: 'Kanban'), isNull);
      await disposeWorkspace(t, rig.container);
    });

    testWidgets('only a button answers: a tap outside or Escape leaves the '
        'question open, and a dialog closed from outside is never a yes', (
      t,
    ) async {
      await rig.pump(t);
      final answer = asks(t, confirm);
      await t.pumpAndSettle();
      await t.tapAt(const Offset(5, 5));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tool.js')), findsOneWidget);
      Navigator.of(t.element(find.byKey(const Key('tool.js')))).pop();
      expect(await answer(), isNull);
      await disposeWorkspace(t, rig.container);
    });

    testWidgets('a long text is cut at 2 000 units, never inside a surrogate '
        'pair', (t) async {
      await rig.pump(t);
      for (final (message, kept) in [
        // The emoji would straddle the cut: it goes whole.
        ('${'a' * 1999}😀b', '${'a' * 1999}…'),
        // It fits before the cut: it stays whole.
        ('${'a' * 1998}😀b', '${'a' * 1998}😀…'),
        // Not over the limit: nothing is cut.
        ('${'a' * 1998}😀', '${'a' * 1998}😀'),
      ]) {
        final answer = asks(
          t,
          BrowserJsDialog(kind: BrowserJsDialogKind.alert, message: message),
        );
        await t.pumpAndSettle();
        final shown = t
            .widget<SelectableText>(
              find.descendant(
                of: find.byKey(const Key('tool.js')),
                matching: find.byType(SelectableText),
              ),
            )
            .data!;
        expect(shown, kept);
        expect(
          utf8.decode(utf8.encode(shown)),
          shown,
          reason: 'no lone surrogate (Flutter cannot paint one)',
        );
        await t.tap(find.byKey(const Key('tool.js.ok')));
        await answer();
      }
      await disposeWorkspace(t, rig.container);
    });
  });

  group('links a page sends outside (D9)', () {
    testWidgets('mailto: and tel: go to the system, http(s) to the browser', (
      t,
    ) async {
      await rig.pump(t);
      final w = await window(t);
      for (final url in [
        'mailto:a@b.c?subject=hi',
        'https://example.com/a?b=1',
        'tel:+84123',
        'http://localhost:3000/',
      ]) {
        await w.actions.openOutside(Uri.parse(url));
      }
      final opener = rig.harness.urlOpener;
      expect(opener.mailOrPhone.map((u) => '$u'), [
        'mailto:a@b.c?subject=hi',
        'tel:+84123',
      ]);
      expect(opener.webLinks.map((u) => '$u'), [
        'https://example.com/a?b=1',
        'http://localhost:3000/',
      ]);
      expect(rig.container.read(terminalTabsProvider).notice, isNull);
      await disposeWorkspace(t, rig.container);
    });

    testWidgets('any other scheme opens nothing, and a toast says so', (
      t,
    ) async {
      await rig.pump(t);
      final ran = <String>[];
      final w = await window(
        t,
        opener: SystemUrlOpener(
          isWindows: false,
          run: (exe, args) async {
            ran.add('$exe ${args.join(' ')}');
            return ProcessResult(0, 0, '', '');
          },
        ),
      );
      const others = [
        'javascript:alert(1)',
        'data:text/html,hi',
        'file:///etc/passwd',
        'ssh://host',
        'sms:123',
        'facetime:x',
        'x-apple.systempreferences:com.apple.preference.security',
      ];
      final logged = await _logged(() async {
        for (final other in others) {
          await w.actions.openOutside(Uri.parse(other));
          expect(
            rig.container.read(terminalTabsProvider).notice,
            isA<LinkOpenFailedNotice>(),
            reason: other,
          );
          rig.container.read(terminalTabsProvider.notifier).dismissNotice();
        }
      });
      expect(ran, isEmpty);
      expect(
        logged,
        List.filled(others.length, 'tool: not opened outside (ArgumentError)'),
        reason: 'D24: the error\'s type, never the link',
      );
      await w.actions.openOutside(Uri.parse('tel:+84123'));
      await w.actions.openOutside(Uri.parse('https://example.com/'));
      expect(ran, [
        '/usr/bin/open tel:+84123',
        '/usr/bin/open https://example.com/',
      ], reason: 'what the system takes still opens');
      await disposeWorkspace(t, rig.container);
    });
  });

  testWidgets('Copy URL puts the tool\'s own URL on the clipboard (R18)', (
    t,
  ) async {
    await rig.pump(t);
    final w = await window(t);
    final tool = rig.add(
      kDefaultWorkspaceId,
      'localhost:3000/board?x=1#top',
      name: 'Board',
    );
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await w.actions.copyUrl(tool);
    expect(copied, 'http://localhost:3000/board?x=1', reason: 'no fragment');
    await disposeWorkspace(t, rig.container);
  });

  group('⌘⇧B with nothing to show (D10, D20)', () {
    Future<void> addFromDialog(WidgetTester t, String url) async {
      await shown(t);
      await t.enterText(find.byKey(const Key('tool.dialog.url')), url);
      await t.tap(find.byKey(const Key('tool.dialog.save')));
    }

    testWidgets('a workspace with no tool asks for one, then shows it', (
      t,
    ) async {
      await rig.pump(t);
      final w = await window(t);
      var toggled = w.actions.toggle(w.context);
      await shown(t);
      await t.tap(find.byKey(const Key('tool.dialog.cancel')));
      expect(await toggled, ToolToggle.nothing);
      expect(rig.container.read(toolRegistryProvider), isEmpty);
      toggled = w.actions.toggle(w.context);
      await addFromDialog(t, 'localhost:5000');
      expect(await toggled, ToolToggle.opened);
      final tool = rig.container.read(toolRegistryProvider).single;
      final dock = rig.container.read(toolDockProvider).of(kDefaultWorkspaceId);
      expect([dock.open, dock.active], [true, tool.id]);
      await disposeWorkspace(t, rig.container);
    });

    testWidgets('without embedding it asks only when the workspace has no '
        'tool, and opens what it added in the browser (R20, D20)', (t) async {
      await rig.pump(t, config: 'tool-embed = off');
      final w = await window(t);
      final opener = rig.harness.urlOpener;
      // Cancelled: nothing is added, nothing opens.
      var toggled = w.actions.toggle(w.context);
      await shown(t);
      await t.tap(find.byKey(const Key('tool.dialog.cancel')));
      expect(await toggled, ToolToggle.nothing);
      expect(rig.container.read(toolRegistryProvider), isEmpty);
      expect(opener.webLinks, isEmpty);
      // Added: the tool opens, in the browser.
      toggled = w.actions.toggle(w.context);
      await addFromDialog(t, 'localhost:5000');
      expect(await toggled, ToolToggle.asked);
      final tool = rig.container.read(toolRegistryProvider).single;
      expect(
        rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).open,
        isFalse,
        reason: 'nothing is shown inside ShellX',
      );
      expect(
        opener.webLinks,
        [tool.uri],
        reason:
            'R20: adding from the window opens the tool; D20: in the browser',
      );
      // With a tool, there is nothing to ask or show.
      toggled = w.actions.toggle(w.context);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tool.dialog')), findsNothing);
      expect(await toggled, ToolToggle.nothing);
      expect(opener.webLinks, hasLength(1));
      await disposeWorkspace(t, rig.container);
    });
  });
}

/// What a test needs to run the window's tool commands.
typedef _Window = ({ToolActions actions, BuildContext context});

/// What [body] sends to `debugPrint`, which is back to normal when it ends
/// (the test framework checks that before the test is over).
Future<List<String>> _logged(Future<void> Function() body) async {
  final lines = <String>[];
  final old = debugPrint;
  debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
  try {
    await body();
  } finally {
    debugPrint = old;
  }
  return lines;
}

/// The rig's window services, with [opener] opening links.
DesktopServices _servicesOpening(TestHarness h, UrlOpener opener) =>
    DesktopServices(
      secureStore: h.secureStore,
      settings: h.settings,
      api: h.api,
      createApi: () => h.api,
      runtimeFactory: FakeAgentRuntime.new,
      sessions: h.sessions,
      keepAwake: h.keepAwake,
      launchAtLogin: h.launchAtLogin,
      notifier: h.notifier,
      urlOpener: opener,
      l10n: h.l10n,
      appVersion: h.appVersion,
      platform: h.platform,
      deviceName: 'Test',
    );
