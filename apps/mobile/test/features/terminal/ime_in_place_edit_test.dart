import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/domain/shellx_terminal.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:xterm/xterm.dart';

/// Mobile Vietnamese input methods (iOS "Simple Telex", VNI) edit the word
/// already typed in place instead of composing it: typing "chao" then a tone
/// key asks the field to become "chào". The terminal keeps the trailing word
/// in the platform document — behind the two `deleteDetection` guard spaces —
/// so the input method has something to edit (third_party/xterm/SHELLX_PATCHES.md).
void main() {
  late ExtraKeysController keys;
  late ShellxTerminal terminal;
  late FocusNode focus;
  late StringBuffer out;
  // The word part (after the two guard spaces) of the document the terminal
  // last set; the keyboard edits from there, not from a full word each time.
  late String content;
  late int seen;

  setUp(() {
    keys = ExtraKeysController();
    terminal = ShellxTerminal(modifiers: keys);
    out = StringBuffer();
    terminal.onOutput = out.write;
    focus = FocusNode();
  });

  tearDown(() => keys.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            focusNode: focus,
            autofocus: true,
            deleteDetection: true,
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    });
    focus.requestFocus();
    await tester.pump();
    await tester.pump();
    content = '';
    seen = 0;
    tester.testTextInput.log.clear();
  }

  /// The word the terminal last wrote into the document (guard stripped).
  String document(WidgetTester tester) {
    final log = tester.testTextInput.log;
    for (; seen < log.length; seen++) {
      if (log[seen].method == 'TextInput.setEditingState') {
        final t = (log[seen].arguments as Map)['text'] as String;
        content = t.startsWith('  ') ? t.substring(2) : t;
      }
    }
    return content;
  }

  /// The input method sets the field to the two guard spaces plus [word],
  /// caret at the end (no composing region — an in-place edit).
  Future<void> ime(WidgetTester tester, String word) async {
    document(tester);
    content = word;
    final text = '  $word';
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    await tester.pump();
  }

  /// Typing [word] one key at a time, each key appended to whatever the
  /// terminal currently holds in the document.
  Future<void> type(WidgetTester tester, String word) async {
    for (var i = 0; i < word.length; i++) {
      await ime(tester, document(tester) + word[i]);
    }
  }

  testWidgets('"chao" then the tone key: the word is retyped as "chào"', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'chao');
    expect(out.toString(), 'chao');

    await ime(tester, 'chào');
    expect(out.toString(), 'chao\x7f\x7fào');

    await ime(tester, 'chào ');
    expect(out.toString(), 'chao\x7f\x7fào ', reason: 'a space ends the word');
  });

  testWidgets('"vieetj" (Telex) becomes "việt"', (tester) async {
    await pump(tester);
    await type(tester, 'vie');
    await ime(tester, 'viê'); // ee -> ê
    await ime(tester, 'viêt'); // t
    await ime(tester, 'việt'); // j -> dot below
    expect(out.toString(), 'vie\x7fêt\x7f\x7fệt');
  });

  testWidgets('a plain word with no in-place edit is sent once', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'ls');
    expect(out.toString(), 'ls');
  });

  testWidgets('a soft Backspace takes the last character off the word', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'chao');
    await ime(tester, 'cha'); // the keyboard drops the last letter
    expect(out.toString(), 'chao\x7f');
    await ime(tester, 'chà'); // then a tone edits the kept word in place
    expect(out.toString(), 'chao\x7f\x7fà');
  });

  testWidgets('a soft Backspace at an empty word eats into the guard', (
    tester,
  ) async {
    await pump(tester);
    // One guard space left: deleteDetection reads it as one cell back.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: ' ',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(out.toString(), '\x7f');
  });

  testWidgets('punctuation ends the word; only the word is kept', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'a.b');
    expect(out.toString(), 'a.b');
    expect(document(tester), 'b', reason: 'only "b" is kept, not "a."');
    // A following in-place tone edits only the kept "b".
    await ime(tester, 'ḅ');
    expect(out.toString(), 'a.b\x7fḅ');
  });
}
