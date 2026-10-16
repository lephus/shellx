import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_text.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// An agent's answer as markdown (V2-2 §5.2), split into blocks so a
/// streaming answer re-renders only its last block. Images are never
/// loaded (their alt text shows); a link opens on tap, http/https only,
/// with a host and without a user name before it (V2-1 B15). A text is split
/// when it changes, not on every build, and the phone builds at most
/// [kShownAnswerChars] characters and [kShownBlocks] blocks of it: the rest
/// is read on the computer.
///
/// The text is plain `Text`, not selectable by itself: `selectable: true` makes an editor of every
/// paragraph, list item and table cell (125 ms against 19 ms to build a hundred blocks). The timeline
/// wraps the whole conversation in one `SelectionArea`, which selects it all.
class AiMarkdown extends StatefulWidget {
  const AiMarkdown({super.key, required this.text, this.dim = false, this.truncated = false, this.cutAction});

  final String text;

  /// A thought: secondary colour.
  final bool dim;

  /// The computer sent only the start of this text (an older page of a long answer).
  final bool truncated;

  /// V2-2b B16: what goes under the hint when the text is cut (here, or by the computer: [truncated]) — the
  /// "Xem đủ" button. Shown exactly when the hint is, so that what the phone cut is decided in this one place.
  final Widget? cutAction;

  @override
  State<AiMarkdown> createState() => _AiMarkdownState();
}

class _AiMarkdownState extends State<AiMarkdown> {
  late ({List<String> blocks, bool cut}) _plan = _split(widget.text);

  @override
  void didUpdateWidget(AiMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _plan = _split(widget.text);
  }

  static ({List<String> blocks, bool cut}) _split(String text) {
    final shown = clipForDisplay(text, maxChars: kShownAnswerChars, maxLines: null);
    final blocks = markdownBlocks(shown.text);
    if (blocks.length <= kShownBlocks) return (blocks: blocks, cut: shown.cut);
    return (blocks: blocks.sublist(0, kShownBlocks), cut: true);
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _plan.blocks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, block) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _Block(key: ValueKey(i), text: block, dim: widget.dim),
          ),
        if (_plan.cut || widget.truncated) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              S.of(context).aiCutText,
              style: context.typo.paragraph13.copyWith(color: context.colors.secondaryText),
            ),
          ),
          ?widget.cutAction,
        ],
      ],
    );
  }
}

/// Builds its markdown once per text: an unchanged block hands Flutter the
/// same widget, so nothing below it rebuilds while the answer streams.
class _Block extends StatefulWidget {
  const _Block({super.key, required this.text, required this.dim});

  final String text;
  final bool dim;

  @override
  State<_Block> createState() => _BlockState();
}

class _BlockState extends State<_Block> {
  Widget? _built;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  @override
  void didUpdateWidget(_Block oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.dim != widget.dim) _built = null;
  }

  @override
  Widget build(BuildContext context) => _built ??= _make(context);

  Widget _make(BuildContext context) {
    final colors = context.colors;
    final base = context.typo.paragraph.copyWith(color: widget.dim ? colors.secondaryText : colors.primaryText);
    final mono = TextStyle(fontFamily: FontFamily.jetBrainsMono, fontSize: 13, color: colors.primaryText);
    return MarkdownBody(
      data: widget.text,
      styleSheet: MarkdownStyleSheet(
        p: base,
        code: mono.copyWith(backgroundColor: colors.primarySoft),
        codeblockDecoration: BoxDecoration(color: colors.primarySoft, borderRadius: BorderRadius.circular(8)),
        codeblockPadding: const EdgeInsets.all(10),
        a: base.copyWith(color: colors.link, decoration: TextDecoration.underline),
        h1: context.typo.heading20.bold.copyWith(color: colors.primaryText),
        h2: context.typo.subHeader.bold.copyWith(color: colors.primaryText),
        h3: base.copyWith(fontWeight: FontWeight.w700),
        listBullet: base,
        blockquote: base.copyWith(color: colors.secondaryText),
      ),
      imageBuilder: (uri, title, alt) => Text(alt ?? '', style: base.copyWith(color: colors.secondaryText)),
      onTapLink: (text, href, title) {
        final uri = href == null ? null : Uri.tryParse(href);
        if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return;
        // A name before the host can pass one site for another ("https://good.com@evil.com" goes to evil.com).
        if (uri.userInfo.isNotEmpty) return;
        getIt<ExternalLinks>().openOrToast(uri);
      },
    );
  }
}
