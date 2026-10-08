/// Rewrites the colour and text-attribute escape sequences (SGR, `CSI ... m`)
/// that xterm 4.0.0's parser misreads, before the text reaches the terminal.
/// Pure Dart, no xterm: the desktop and the phone both put every output
/// string through one filter per terminal.
///
/// What xterm 4.0.0 gets wrong (each was observed with Claude Code, whose
/// Ink/chalk output uses all of them):
///
/// * It ignores the private prefix of `CSI > 4;2 m` (modifyOtherKeys on,
///   sent by Claude Code at start) and `CSI > 4 m` (off) and runs them as SGR
///   4 and 2: underline and faint, which nothing then clears. Such sequences
///   (a private prefix `< = > ?` or an intermediate byte before `m`) are not
///   SGR and are dropped.
/// * SGR 22 (normal intensity, chalk's close for bold and dim) clears faint
///   only. It is sent as `21;22` (xterm reads 21 as bold off).
/// * It skips the colon of ISO 8613-6 sub-parameters and glues the digits:
///   `4:0` (underline off) becomes 40 (black background), `4:3` becomes 43,
///   `38:2::R:G:B` becomes one huge number. Colon colours are rewritten to
///   the semicolon form, `4:0` to 24, other `4:x` to 4, other colon groups
///   keep their first number.
/// * Underline colour (58, 59) is unsupported and its `58;2;R;G;B` form
///   would be read as faint, 255 and reset: it is dropped.
///
/// Everything else, including every other escape sequence and all text, is
/// passed through byte for byte. The filter is streaming: a sequence cut by
/// the end of a chunk is held until the next one, at most [maxSequence]
/// characters; anything longer or malformed is passed through unchanged.
final class SgrFilter {
  SgrFilter({this.maxSequence = 96});

  /// The longest `ESC [ ... final` that is held across chunks or rewritten.
  final int maxSequence;

  String _held = '';

  /// Returns [chunk] with the SGR sequences rewritten. May return less than
  /// was given (the tail of an unfinished sequence) and more (what was held).
  String filter(String chunk) {
    final String text;
    if (_held.isEmpty) {
      if (!chunk.contains('\x1b')) return chunk;
      text = chunk;
    } else {
      text = _held + chunk;
      _held = '';
    }
    final out = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final esc = text.indexOf('\x1b', i);
      if (esc < 0) {
        out.write(i == 0 ? text : text.substring(i));
        break;
      }
      out.write(text.substring(i, esc));
      if (esc + 1 >= text.length) {
        _held = '\x1b';
        break;
      }
      if (text.codeUnitAt(esc + 1) != 0x5b /* [ */ ) {
        out.write('\x1b');
        i = esc + 1;
        continue;
      }
      // ESC [ params(0x30-0x3F)* intermediates(0x20-0x2F)* final(0x40-0x7E)
      var j = esc + 2;
      var end = -1;
      while (j < text.length && j - esc <= maxSequence) {
        final u = text.codeUnitAt(j);
        if (u >= 0x40 && u <= 0x7e) {
          end = j;
          break;
        }
        if (u < 0x20 || u > 0x3f) break; // not a CSI: let xterm judge
        j++;
      }
      if (end < 0) {
        if (j >= text.length && j - esc <= maxSequence) {
          _held = text.substring(esc); // cut by the chunk end
          break;
        }
        out.write('\x1b');
        i = esc + 1;
        continue;
      }
      if (text.codeUnitAt(end) == 0x6d /* m */ ) {
        out.write(
          _sgr(text.substring(esc + 2, end)) ?? text.substring(esc, end + 1),
        );
      } else {
        out.write(text.substring(esc, end + 1));
      }
      i = end + 1;
    }
    return out.toString();
  }

  /// The replacement for `ESC [ body m` ('' drops it), or null to keep it.
  static String? _sgr(String body) {
    if (body.isEmpty) return null;
    final first = body.codeUnitAt(0);
    var hasIntermediate = false;
    for (var k = 0; k < body.length; k++) {
      final u = body.codeUnitAt(k);
      if (u >= 0x20 && u <= 0x2f) hasIntermediate = true;
    }
    if ((first >= 0x3c && first <= 0x3f) || hasIntermediate) {
      return ''; // not SGR
    }
    // Fast path: nothing here that needs a rewrite.
    if (!body.contains(':') &&
        !body.contains('22') &&
        !body.contains('58') &&
        !body.contains('59')) {
      return null;
    }

    final groups = body.split(';').map((g) => g.split(':')).toList();
    final out = <String>[];
    var g = 0;
    while (g < groups.length) {
      final group = groups[g];
      final head = int.tryParse(group[0]);
      g++;
      switch (head) {
        case 38 || 48:
          if (group.length > 1) {
            final sub = group.sublist(1);
            if (sub[0] == '5' && sub.length >= 2) {
              out.addAll(['$head', '5', sub[1]]);
            } else if (sub[0] == '2' && sub.length >= 4) {
              final rgb = sub.sublist(sub.length - 3);
              out.addAll(['$head', '2', ...rgb]);
            }
          } else {
            // 38;5;N and 38;2;R;G;B: copy the arguments so their numbers
            // (22, say) are not taken for attributes.
            final mode = g < groups.length ? groups[g][0] : '';
            final n = mode == '5' ? 2 : (mode == '2' ? 4 : 0);
            out.add('$head');
            for (var k = 0; k < n && g < groups.length; k++, g++) {
              out.add(groups[g][0]);
            }
          }
        case 58:
          if (group.length == 1) {
            final mode = g < groups.length ? groups[g][0] : '';
            g += mode == '5' ? 2 : (mode == '2' ? 4 : 0);
            if (g > groups.length) g = groups.length;
          }
        case 59:
          break;
        case 4 when group.length > 1:
          out.add(group[1] == '0' ? '24' : '4');
        case 22:
          out.addAll(['21', '22']);
        default:
          out.add(group[0]);
      }
    }
    return out.isEmpty ? '' : '\x1b[${out.join(';')}m';
  }
}
