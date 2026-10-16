import 'package:shellx_mobile/core/core.dart';

/// [text] with each key of [parts] drawn in [partStyle] — and tappable when its value is not
/// null. Keeps localized sentences whole in the ARB files while the design bolds or links words
/// inside them ("shellx.pro", "Ghép nối điện thoại…", a machine name, "Điều khoản").
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    super.key,
    required this.parts,
    required this.style,
    required this.partStyle,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final Map<String, VoidCallback?> parts;
  final TextStyle style;
  final TextStyle partStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      // The earliest remaining part wins.
      MapEntry<String, VoidCallback?>? next;
      var at = -1;
      for (final entry in parts.entries) {
        if (entry.key.isEmpty) continue;
        final index = rest.indexOf(entry.key);
        if (index >= 0 && (at < 0 || index < at)) {
          at = index;
          next = entry;
        }
      }
      if (next == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (at > 0) spans.add(TextSpan(text: rest.substring(0, at)));
      final onTap = next.value;
      spans.add(
        onTap == null
            ? TextSpan(text: next.key, style: partStyle)
            : WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: onTap,
                  child: Text(next.key, style: style.merge(partStyle)),
                ),
              ),
      );
      rest = rest.substring(at + next.key.length);
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: textAlign,
    );
  }
}
