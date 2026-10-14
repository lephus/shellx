import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

void main() {
  testWidgets('flutter_markdown_plus renders a heading, a list and code', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: '# Title\n\n- one\n- two\n\n```dart\nvoid main() {}\n```',
          ),
        ),
      ),
    );
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.textContaining('void main()'), findsOneWidget);
  });

  testWidgets('re_editor shows read-only highlighted code', (t) async {
    final controller = CodeLineEditingController.fromText(
      'void main() {}\nint x = 1;',
    );
    addTearDown(controller.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: controller,
            readOnly: true,
            autofocus: false,
            showCursorWhenReadOnly: false,
            style: CodeEditorStyle(
              codeTheme: CodeHighlightTheme(
                languages: {'dart': CodeHighlightThemeMode(mode: langDart)},
                theme: atomOneDarkTheme,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(controller.codeLines.length, 2);
    await t.pumpWidget(const SizedBox());
  });

  test('diff_match_patch diffs two texts', () {
    final d = dmp.diff('a\nb\nc\n', 'a\nB\nc\n', checklines: false);
    expect(d.any((x) => x.operation == dmp.DIFF_INSERT), isTrue);
    expect(d.any((x) => x.operation == dmp.DIFF_DELETE), isTrue);
  });
}
