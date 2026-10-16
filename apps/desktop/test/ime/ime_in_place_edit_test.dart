import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/ime_compose_reset.dart';
import 'package:xterm/xterm.dart';

/// macOS Vietnamese Telex (Apple's, "Simple Telex") does not compose: each
/// key is inserted at once and a tone or vowel key edits the word already
/// typed in place ("chao" + "f" replaces "chao" with "chào"). The terminal's
/// document keeps the word so the input method can see it
/// (third_party/xterm/SHELLX_PATCHES.md).
void main() {
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);
  late Terminal terminal;
  late StringBuffer out;
  // What the platform's document holds: the input method's last edit,
  // unless the terminal set it since (TextInput.setEditingState).
  late String doc;
  late int seen;


  Future<void> pump(WidgetTester tester) async {
    out = StringBuffer();
    terminal = Terminal()..onOutput = out.write;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ImeComposeReset(
          child: TerminalView(terminal, focusNode: focus, autofocus: true),
        ),
      ),
    );
    await tester.pump();
    doc = '';
    seen = 0;
    tester.testTextInput.log.clear();
  }

  String document(WidgetTester tester) {
    final log = tester.testTextInput.log;
    for (; seen < log.length; seen++) {
      if (log[seen].method == 'TextInput.setEditingState') {
        doc = (log[seen].arguments as Map)['text'] as String;
      }
    }
    return doc;
  }

  /// The input method sets the document to [text], caret at the end.
  Future<void> ime(WidgetTester tester, String text) async {
    document(tester);
    doc = text;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    await tester.pump();
  }

  /// Typing [word] one key at a time, each key inserted at once.
  Future<void> type(WidgetTester tester, String word) async {
    for (var i = 1; i <= word.length; i++) {
      await ime(tester, document(tester) + word[i - 1]);
    }
  }

  testWidgets('"chao" then "f": the word is retyped as "chào"', (tester) async {
    await pump(tester);
    await type(tester, 'chao');
    expect(out.toString(), 'chao');
    expect(document(tester), 'chao');

    await ime(tester, 'chào');
    expect(out.toString(), 'chao\x7f\x7fào');
    expect(document(tester), 'chào');

    await ime(tester, 'chào ');
    expect(out.toString(), 'chao\x7f\x7fào ');
    expect(document(tester), '', reason: 'a space ends the word');
  }, variant: macOS);

  testWidgets('"vieetj" (Telex) becomes "việt"', (tester) async {
    await pump(tester);
    await type(tester, 'vie');
    await ime(tester, 'viê'); // e
    await ime(tester, 'viêt'); // t
    await ime(tester, 'việt'); // j
    expect(
      out.toString(),
      'vie\x7fê'
      't\x7f\x7fệt',
    );
    expect(document(tester), 'việt');
  }, variant: macOS);

  testWidgets('Backspace takes the last character off the word', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'chao');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(out.toString(), 'chao\x7f');
    expect(document(tester), 'cha');

    await ime(tester, 'chà');
    expect(out.toString(), 'chao\x7f\x7fà');
  }, variant: macOS);

  testWidgets('Enter ends the word', (tester) async {
    await pump(tester);
    await type(tester, 'ls');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(out.toString(), 'ls\r');
    expect(document(tester), '');
    await type(tester, 'a');
    expect(out.toString(), 'ls\ra');
  }, variant: macOS);

  testWidgets('punctuation ends the word; only the word is kept', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'a.b');
    expect(out.toString(), 'a.b');
    expect(document(tester), 'b');
  }, variant: macOS);

  testWidgets('the kept word is at most 32 characters', (tester) async {
    await pump(tester);
    await type(tester, 'x' * 40);
    expect(out.toString(), 'x' * 40);
    expect(document(tester), 'x' * 32);
  }, variant: macOS);

  testWidgets('marked text after a kept word is composed, then committed', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'ab');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abか',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 2, end: 3),
      ),
    );
    await tester.pump();
    expect(out.toString(), 'ab');
    await ime(tester, 'ab家');
    expect(out.toString(), 'ab家');
  }, variant: macOS);

  testWidgets('a surrogate pair is deleted as one character', (tester) async {
    await pump(tester);
    await ime(tester, 'a😀'); // not a word: only "a" was the word before it
    expect(out.toString(), 'a😀');
    expect(document(tester), '');
  }, variant: macOS);

  testWidgets('other platforms keep upstream behaviour: the document is '
      'emptied after every character', (tester) async {
    await pump(tester);
    await ime(tester, 'c');
    expect(document(tester), '');
    await ime(tester, 'h');
    expect(out.toString(), 'ch');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
