/// A11 D11: the line-editing keys macOS users expect at a prompt, sent as
/// the control sequences readline, zle and fish all bind. xterm ignores the
/// Cmd key, so these are window actions (not input handlers) and they step
/// aside on the alternate screen, where Ctrl-A would be vim's "increment".
enum EditLineOp {
  lineStart('line_start'),
  lineEnd('line_end'),
  deleteLine('delete_line'),
  deleteWord('delete_word'),
  deleteWordForward('delete_word_forward');

  const EditLineOp(this.wire);
  final String wire;

  static EditLineOp? fromWire(String? text) {
    for (final op in values) {
      if (op.wire == text) return op;
    }
    return null;
  }
}

String editLineSequence(EditLineOp op) => switch (op) {
  EditLineOp.lineStart => '\x01',
  EditLineOp.lineEnd => '\x05',
  EditLineOp.deleteLine => '\x15',
  EditLineOp.deleteWord => '\x1b\x7f',
  EditLineOp.deleteWordForward => '\x1bd',
};

bool canEditLine({required bool exited, required bool altBuffer}) =>
    !exited && !altBuffer;
