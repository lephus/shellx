import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';
import 'package:shellx_desktop/src/ui/ai/ai_file_viewer.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';
import '../../support/fake_project.dart';

/// V2-1 D17, D18, §4.4: the read-only viewer and "Mention in chat".
void main() {
  Future<(FakeAiRuntimes, AiRuntime)> viewer(
    WidgetTester t,
    Map<String, String> files, {
    String path = 'README.md',
  }) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(
      t,
      Column(
        children: [
          Expanded(child: AiFileViewer(path: path)),
          const AiDock(),
        ],
      ),
      runtime: runtime,
      overrides: [
        aiProjectFilesProvider.overrideWithValue(FakeProject(testAiCwd, files)),
      ],
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    return (fakes, runtime);
  }

  testWidgets('"Mention in chat" puts @path in the composer, and the file '
      'goes along with the message as a resource_link', (t) async {
    final (fakes, runtime) = await viewer(t, {'README.md': '# Hi\n'});
    await t.tap(find.byKey(const Key('ai.viewer.mention')));
    await t.pump();
    final field = t.widget<TextField>(find.byKey(const Key('ai.composer')));
    expect(field.controller!.text, '@README.md ');
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
    await t.enterText(find.byKey(const Key('ai.composer')), '@README.md what?');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt.first, {'type': 'text', 'text': '@README.md what?'});
    expect(prompt.last, {
      'type': 'resource_link',
      'uri': Uri.file('$testAiCwd/README.md').toString(),
      'name': 'README.md',
      'title': 'README.md',
    });
    await runtime.dispose();
  });

  testWidgets('a minified file is one very long line: only its first 2 000 '
      'characters are laid out (smoothness)', (t) async {
    final (_, runtime) = await viewer(t, {
      'min.txt': 'x' * 5000,
    }, path: 'min.txt');
    final code = t.widget<CodeEditor>(find.byKey(const Key('ai.viewer.code')));
    expect(code.maxLengthSingleLineRendering, 2000);
    await runtime.dispose();
  });
}
