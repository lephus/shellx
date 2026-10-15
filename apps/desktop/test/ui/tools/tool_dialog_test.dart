import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/tools/tool_dialogs.dart';

import '../../support/config_workspace.dart';
import '../../support/fake_local_sessions.dart';
import '../../support/tool_harness.dart';

void main() {
  late ToolRig rig;
  setUp(() => rig = ToolRig());

  /// The dialog alone; what Add does with it is the window's (Task 13).
  Future<ToolDraft?> Function() openDialog(WidgetTester t) {
    ToolDraft? result;
    var done = false;
    unawaited(
      showToolDialog(
        t.element(find.byType(TerminalWorkspacePage)),
        ws: kDefaultWorkspaceId,
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
}
