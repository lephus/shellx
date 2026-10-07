import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/terminal/edit_line.dart';

void main() {
  test('each op sends what readline, zle and fish bind (D11)', () {
    expect(editLineSequence(EditLineOp.lineStart), '\x01');
    expect(editLineSequence(EditLineOp.lineEnd), '\x05');
    expect(editLineSequence(EditLineOp.deleteLine), '\x15');
    expect(editLineSequence(EditLineOp.deleteWord), '\x1b\x7f');
    expect(editLineSequence(EditLineOp.deleteWordForward), '\x1bd');
  });

  test('wire names round-trip and an unknown one is rejected', () {
    for (final op in EditLineOp.values) {
      expect(EditLineOp.fromWire(op.wire), op);
    }
    expect(EditLineOp.fromWire('nope'), isNull);
  });

  test(
    'only a live pane on the main screen takes the keys (vim gets its own)',
    () {
      expect(canEditLine(exited: false, altBuffer: false), isTrue);
      expect(canEditLine(exited: false, altBuffer: true), isFalse);
      expect(canEditLine(exited: true, altBuffer: false), isFalse);
    },
  );

  test('the action parses with each op and refuses others', () {
    for (final op in EditLineOp.values) {
      final r = parseKeyAction('edit_line:${op.wire}');
      expect(r.problem, isNull);
      expect(r.action, KeyAction('edit_line', op.wire));
    }
    expect(parseKeyAction('edit_line:sideways').problem, isNotNull);
    expect(parseKeyAction('edit_line').problem, isNotNull);
  });

  test('macOS defaults bind the five chords; Windows binds none', () {
    final mac = defaultKeyBindings(TargetPlatform.macOS);
    KeyChord? chordOf(String param) => mac
        .where((b) => b.action == KeyAction('edit_line', param))
        .map((b) => b.sequence.single)
        .firstOrNull;
    expect(
      chordOf('line_start'),
      const KeyChord(LogicalKeyboardKey.arrowLeft, meta: true),
    );
    expect(
      chordOf('line_end'),
      const KeyChord(LogicalKeyboardKey.arrowRight, meta: true),
    );
    expect(
      chordOf('delete_line'),
      const KeyChord(LogicalKeyboardKey.backspace, meta: true),
    );
    expect(
      chordOf('delete_word'),
      const KeyChord(LogicalKeyboardKey.backspace, alt: true),
    );
    expect(
      chordOf('delete_word_forward'),
      const KeyChord(LogicalKeyboardKey.delete, alt: true),
    );
    expect(
      defaultKeyBindings(
        TargetPlatform.windows,
      ).where((b) => b.action.name == 'edit_line'),
      isEmpty,
    );
  });
}
