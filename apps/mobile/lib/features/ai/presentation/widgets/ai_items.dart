import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_text.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_markdown.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// One conversation item on the phone (V2-2 §5.2). The timeline hands the very same widget to Flutter
/// for as long as the item is the one the mirror holds (the mirror replaces an item when the desktop
/// sends a newer rev), so it rebuilds only when the desktop changed it, and the state of its element
/// (an open card, an unfolded thought) survives the change.
class AiItemView extends StatelessWidget {
  const AiItemView({super.key, required this.item, required this.agentName, this.clock});

  final MirrorItem item;
  final String agentName;

  /// The page's clock, which ticks every second while a turn runs: a tool call that is running counts
  /// its time by it (and only its few characters are rebuilt).
  final ReadonlySignal<DateTime>? clock;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    return switch (item) {
      MirrorText(kind: MirrorTextKind.user) => _UserBubble(item),
      MirrorText(kind: MirrorTextKind.agent) => _AgentText(item),
      MirrorText(kind: MirrorTextKind.thought) => _Thought(item),
      MirrorTool() => AiToolCard(tool: item, clock: clock),
      MirrorAsk() => _AskLine(item, agentName),
      MirrorTurnEnd() => _TurnEnd(item),
      MirrorNotice() => _Notice(item, agentName),
      MirrorUnknown() => _OnComputer(item),
    };
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.item);
  final MirrorText item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shown = clipForDisplay(item.text, maxChars: kShownTextChars, maxLines: null);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.primarySoft,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Plain text: the timeline's one SelectionArea makes it selectable, without an editor of its own.
              Text(shown.text, style: context.typo.paragraph.copyWith(color: colors.primaryText)),
              if (shown.cut || item.fullLength != null) _Hint(S.of(context).aiCutText),
              // V2-2b B24: written on a phone (this one or another), as the computer says too.
              if (item.fromPhone)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    S.of(context).aiFromPhone,
                    key: const Key('ai.user.fromPhone'),
                    style: context.typo.metadata12.copyWith(color: colors.secondaryText),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentText extends StatelessWidget {
  const _AgentText(this.item);
  final MirrorText item;

  @override
  Widget build(BuildContext context) => AiMarkdown(text: item.text, truncated: item.fullLength != null);
}

/// Folded by default (V2-1 §4.2).
class _Thought extends StatefulWidget {
  const _Thought(this.item);
  final MirrorText item;

  @override
  State<_Thought> createState() => _ThoughtState();
}

class _ThoughtState extends State<_Thought> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          // At least 44 points under the finger, the whole row.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.secondaryText),
                4.sizedWidth,
                Text(S.of(context).aiThought, style: context.typo.paragraph13.copyWith(color: colors.secondaryText)),
              ],
            ),
          ),
        ),
        if (_open) AiMarkdown(text: widget.item.text, dim: true, truncated: widget.item.fullLength != null),
      ],
    );
  }
}

/// The question's place in the conversation; its form is in the dock.
class _AskLine extends StatelessWidget {
  const _AskLine(this.item, this.agentName);
  final MirrorAsk item;
  final String agentName;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final status = switch (item.status) {
      'open' => s.aiAskWaiting,
      'accepted' || 'completed' => s.aiAskAnswered,
      'declined' || 'auto_declined' => s.aiAskDeclined,
      'cancelled' => s.aiAskCancelled,
      _ => item.status,
    };
    return _CardFrame(
      warn: item.open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.aiAskTitle(agentName), style: context.typo.paragraph13.bold.copyWith(color: colors.secondaryText)),
          4.sizedHeight,
          Text(item.request?.message ?? '', style: context.typo.paragraph.copyWith(color: colors.primaryText)),
          4.sizedHeight,
          Text(
            item.status == 'auto_declined' ? s.aiAskUnsupported : status,
            style: context.typo.paragraph13.copyWith(color: item.open ? colors.warn : colors.secondaryText),
          ),
        ],
      ),
    );
  }
}

class _TurnEnd extends StatelessWidget {
  const _TurnEnd(this.item);
  final MirrorTurnEnd item;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final time = AiWords.clock(item.elapsed);
    final head = switch (item.outcome) {
      'cancelled' => s.aiTurnStopped(item.turn, time),
      'interrupted' => s.aiTurnInterrupted(item.turn),
      'failed' => s.aiTurnFailed(item.turn),
      _ => s.aiTurnSummary(item.turn, time),
    };
    final files = item.files;
    final parts = [
      head,
      if (files != null && files > 0) '${s.aiTurnFiles(files)} +${item.plus} −${item.minus}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          // The summary can be long on a narrow phone ("Đã dừng lượt 12 · 1:02:03 · 120 tệp đổi +1234
          // −567"): it wraps within most of the width and the lines at its sides take what is left.
          LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Expanded(child: Divider(color: colors.divider)),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      parts.join(' · '),
                      textAlign: TextAlign.center,
                      style: context.typo.metadata12.copyWith(color: colors.secondaryText),
                    ),
                  ),
                ),
                Expanded(child: Divider(color: colors.divider)),
              ],
            ),
          ),
          if (item.error != null) _Hint(item.error!),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.item, this.agentName);
  final MirrorNotice item;
  final String agentName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: item.resolved ? 0.55 : 1,
      child: _CardFrame(
        warn: !item.resolved,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: item.resolved ? colors.secondaryText : colors.warn),
            8.sizedWidth,
            Expanded(
              child: Text(
                AiWords.notice(S.of(context), item, agentName),
                style: context.typo.paragraph13.copyWith(color: colors.primaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card the phone cannot draw: too large to send (`big`), or a newer computer's kind. Read on the
/// computer, each with its own words.
class _OnComputer extends StatelessWidget {
  const _OnComputer(this.item);
  final MirrorUnknown item;

  @override
  Widget build(BuildContext context) => _CardFrame(child: _Hint(AiWords.itemOnComputer(S.of(context), item)));
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, style: context.typo.paragraph13.copyWith(color: context.colors.secondaryText)),
  );
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.child,
    this.warn = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  });
  final Widget child;
  final bool warn;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: warn ? colors.warnSoft : colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: warn ? colors.warn.withValues(alpha: 0.5) : colors.divider),
      ),
      child: child,
    );
  }
}

/// One tool call (V2-1 §4.2 on a phone): a one-line header with its state;
/// a tap shows the diff, the output or the input. Open by itself while it
/// waits for a permission.
class AiToolCard extends StatefulWidget {
  const AiToolCard({super.key, required this.tool, this.clock});

  final MirrorTool tool;
  final ReadonlySignal<DateTime>? clock;

  @override
  State<AiToolCard> createState() => _AiToolCardState();
}

class _AiToolCardState extends State<AiToolCard> {
  bool? _open;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final t = widget.tool;
    final waiting = t.permission == MirrorPermissionState.waiting;
    final open = _open ?? waiting;
    final hasBody = t.diffs.isNotEmpty || t.output != null || t.input != null;
    // What hangs below the header (the user's choice, the open body) needs room under it; a header alone
    // is the whole card.
    final below = t.answerKind != null || open;
    return _CardFrame(
      warn: waiting,
      // The header is the button and is at least 44 points high: it takes the card's vertical padding
      // inside itself, so a single line is not taller than it must be.
      padding: EdgeInsets.fromLTRB(12, 0, 12, below ? 10 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasBody ? () => setState(() => _open = !open) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Icon(_icon(t.kind), size: 18, color: colors.secondaryText),
                  8.sizedWidth,
                  Expanded(
                    child: Text(
                      AiWords.toolTitle(s, t),
                      maxLines: open ? 4 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.paragraph13.copyWith(
                        fontFamily: FontFamily.jetBrainsMono,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  8.sizedWidth,
                  _ToolState(tool: t, clock: widget.clock),
                  if (hasBody)
                    Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.secondaryText),
                ],
              ),
            ),
          ),
          if (t.answerKind != null) ...[
            4.sizedHeight,
            Text(
              s.aiYouChose(
                t.answerName == null || t.answerName!.isEmpty
                    ? _optionWord(s, t.answerKind!)
                    : '${_optionWord(s, t.answerKind!)} (${t.answerName})',
              ),
              style: context.typo.metadata12.copyWith(color: colors.secondaryText),
            ),
          ],
          if (open) ...[
            for (final d in t.diffs)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AiDiffView(diff: d),
              ),
            if (t.moreDiffs > 0) _Hint(s.aiMoreDiffs(t.moreDiffs)),
            if (t.output != null) Padding(padding: const EdgeInsets.only(top: 8), child: _Output(t.output!)),
            if (t.output == null && t.kind == ToolKind.execute && t.end == 'completed') _Hint(s.aiNoOutput),
            if (t.input != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _Mono(t.input!, maxChars: kShownInputChars),
              ),
          ],
        ],
      ),
    );
  }

  static String _optionWord(S s, PermissionKind kind) => switch (kind) {
    PermissionKind.allowOnce => s.aiPermAllowOnce,
    PermissionKind.allowAlways => s.aiPermAllowAlways,
    PermissionKind.rejectOnce => s.aiPermRejectOnce,
    PermissionKind.rejectAlways => s.aiPermRejectAlways,
    PermissionKind.other => '',
  };

  static IconData _icon(ToolKind? kind) => switch (kind) {
    ToolKind.read => Icons.description_outlined,
    ToolKind.edit => Icons.edit_outlined,
    ToolKind.delete => Icons.delete_outline,
    ToolKind.move => Icons.drive_file_rename_outline,
    ToolKind.search => Icons.search,
    ToolKind.execute => Icons.terminal,
    ToolKind.think => Icons.psychology_outlined,
    ToolKind.fetch => Icons.public,
    ToolKind.switchMode => Icons.swap_horiz,
    ToolKind.other || null => Icons.extension_outlined,
  };
}

/// "chờ", "chờ bạn", "đang chạy · 2,1 s", ✓, "bị từ chối", "đã dừng", "lỗi".
class _ToolState extends StatelessWidget {
  const _ToolState({required this.tool, this.clock});
  final MirrorTool tool;
  final ReadonlySignal<DateTime>? clock;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final t = tool;
    final style = context.typo.metadata12;
    if (t.permission == MirrorPermissionState.waiting) {
      return Text(s.aiToolAwaiting, style: style.copyWith(color: colors.warn));
    }
    switch (t.end) {
      case 'completed':
        return Icon(Icons.check, size: 16, color: colors.ok, semanticLabel: s.aiToolDone);
      case 'failed':
        final rejected = t.answerKind?.isReject ?? false;
        return Text(rejected ? s.aiToolRejected : s.aiToolFailed, style: style.copyWith(color: colors.error));
      case 'stopped':
        return Text(s.aiToolStopped, style: style.copyWith(color: colors.secondaryText));
    }
    final startedAt = t.startedAt;
    if (t.status == ToolCallStatus.inProgress && startedAt != null) {
      final locale = Localizations.localeOf(context).toLanguageTag();
      Widget running(DateTime now) => Text(
        s.aiToolRunningFor(AiWords.elapsed(now.difference(startedAt), locale: locale)),
        style: style.copyWith(color: colors.link),
      );
      // Counting needs the page's clock; only this text follows it.
      final clock = this.clock;
      return clock == null ? running(DateTime.now()) : Watch((context) => running(clock.value));
    }
    return Text(s.aiToolPending, style: style.copyWith(color: colors.secondaryText));
  }
}

/// A file's change as −/+ lines (V2-2 D6), scrolling sideways. The lines are made once per diff, and
/// the phone lays out at most [kShownOutputChars] characters and [kShownLines] lines of each side.
class AiDiffView extends StatefulWidget {
  const AiDiffView({super.key, required this.diff});

  final MirrorDiff diff;

  @override
  State<AiDiffView> createState() => _AiDiffViewState();
}

class _AiDiffViewState extends State<AiDiffView> {
  late List<DiffLine> _lines;
  late bool _cut;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void didUpdateWidget(AiDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.diff, widget.diff)) _compute();
  }

  void _compute() {
    final diff = widget.diff;
    final after = clipForDisplay(diff.newText, maxChars: kShownOutputChars);
    final oldText = diff.oldText;
    final before = oldText == null ? null : clipForDisplay(oldText, maxChars: kShownOutputChars);
    _lines = diffLines(before?.text, after.text);
    _cut = diff.cut || after.cut || (before?.cut ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final diff = widget.diff;
    final lines = _lines;
    const mono = TextStyle(fontFamily: FontFamily.jetBrainsMono, fontSize: 12, height: 1.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          [
            AiWords.fileName(diff.path),
            if (diff.oldText == null) s.aiCreated,
            '+${diff.plus} −${diff.minus}',
          ].join(' · '),
          style: context.typo.metadata12.bold.copyWith(color: colors.secondaryText),
        ),
        4.sizedHeight,
        Container(
          decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  for (final (i, l) in lines.indexed)
                    TextSpan(
                      text: '${l.mark} ${l.text}${i == lines.length - 1 ? '' : '\n'}',
                      style: mono.copyWith(
                        color: l.mark == ' ' ? colors.secondaryText : colors.primaryText,
                        backgroundColor: switch (l.mark) {
                          '+' => colors.okDot.withValues(alpha: 0.16),
                          '-' => colors.error.withValues(alpha: 0.12),
                          _ => null,
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_cut) _Hint(s.aiFromComputerOnly),
      ],
    );
  }
}

class _Output extends StatelessWidget {
  const _Output(this.output);
  final MirrorOutput output;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Mono(output.head),
        if (output.cut) ...[_Hint(s.aiCutLines(output.lines)), _Mono(output.tail)],
      ],
    );
  }
}

/// Monospace text that scrolls sideways. The computer sends tool output, and the input of a call, cut
/// to a few KiB; the phone cuts again to [maxChars] characters and [kShownLines] lines, since one line
/// of a megabyte would take seconds to lay out (V2-2 D4).
class _Mono extends StatelessWidget {
  const _Mono(this.text, {this.maxChars = kShownOutputChars});
  final String text;
  final int maxChars;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shown = clipForDisplay(text, maxChars: maxChars);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              shown.text,
              style: TextStyle(
                fontFamily: FontFamily.jetBrainsMono,
                fontSize: 12,
                height: 1.35,
                color: colors.primaryText,
              ),
            ),
          ),
        ),
        if (shown.cut) _Hint(S.of(context).aiFromComputerOnly),
      ],
    );
  }
}
