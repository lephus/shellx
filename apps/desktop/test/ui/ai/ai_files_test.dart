import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_project.dart';

/// V2-1 D18, §4.4 (Files), §4.2 (`read` cards): the tree and the viewer.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<(ProviderContainer, FakeProject)> pane(
    WidgetTester t, {
    List<List<Map<String, Object?>>> turns = const [],
  }) async {
    final files = FakeProject(testAiCwd, {
      '.gitignore': 'dist/\n',
      'lib/a.dart': 'one\ntwo\nthree\n',
      'README.md': '# Hi\n',
      'dist/app.js': 'x\n',
    });
    files.onSnapshot = (ref) {
      if (ref.endsWith('/1')) files.files['lib/new.dart'] = 'n\n';
    };
    final fakes = FakeAiRuntimes(
      FakeScenario(turns: turns),
      checkpoints: files,
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiProjectFilesProvider.overrideWithValue(files),
      ],
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    return (c, files);
  }

  Future<void> files(WidgetTester t) async {
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.panel.files')));
    await t.pumpAndSettle();
  }

  testWidgets('the tree: folders first, ignored dimmed, M/A after a turn; a '
      'folder opens in place', (t) async {
    final (c, _) = await pane(
      t,
      turns: [
        [FakeSteps.text('ok')],
      ],
    );
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await files(t);
    for (final path in ['dist', 'lib', '.gitignore', 'README.md']) {
      expect(find.byKey(ValueKey('ai.file.$path')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai.file.dist')),
        matching: find.text('ignored'),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('ai.file.lib')));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai.file.lib/new.dart')),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the tree looks again when its tab comes back to the front '
      '(D18)', (t) async {
    final (c, project) = await pane(t);
    await files(t);
    project.files['NEW.md'] = 'n\n';
    final tabs = c.read(terminalTabsProvider.notifier);
    final ai = c.read(terminalTabsProvider).selectedId!;
    tabs.select(c.read(terminalTabsProvider).tabs.first.id);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai.file.NEW.md')), findsNothing);
    tabs.select(ai);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai.file.NEW.md')), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a file opens read-only; "Mention in chat" puts @path in the '
      'composer', (t) async {
    final (c, _) = await pane(t);
    await files(t);
    await t.tap(find.byKey(const ValueKey('ai.file.README.md')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    final code = t.widget<CodeEditor>(find.byKey(const Key('ai.viewer.code')));
    expect(code.controller!.text, '# Hi\n');
    expect(code.readOnly, isTrue);
    expect(find.text('read-only'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.viewer.mention')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.viewer')), findsNothing);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .controller!
          .text,
      '@README.md ',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a read card opens the file at its line', (t) async {
    final (c, _) = await pane(
      t,
      turns: [
        [
          FakeSteps.tool(
            't1',
            'Read a.dart',
            kind: 'read',
            status: 'completed',
            locations: [
              {'path': '$testAiCwd/lib/a.dart', 'line': 2},
            ],
          ),
        ],
      ],
    );
    await t.enterText(find.byKey(const Key('ai.composer')), 'read');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.tap(find.text('lib/a.dart'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    final code = t.widget<CodeEditor>(find.byKey(const Key('ai.viewer.code')));
    expect(code.controller!.selection.baseIndex, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.viewer')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
