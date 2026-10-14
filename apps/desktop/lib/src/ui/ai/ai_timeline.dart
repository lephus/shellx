import 'package:flutter/material.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_markdown.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';
import 'ai_tool_card.dart';

/// One conversation item's widget (spec §4.2).
Widget aiTimelineItem(TimelineItem item) => switch (item) {
  UserItem() => AiUserMessage(item: item),
  AgentTextItem() => AiAgentText(item: item),
  ThoughtItem() => AiThought(item: item),
  ToolItem() => AiToolCard(item: item),
  AskItem() => _AskFallback(item: item),
  TurnEndItem() => const SizedBox(height: ShellxSpace.s8),
  NoticeItem() => const SizedBox.shrink(),
};

/// The conversation (spec §4.1, §4.2). Smoothness:
/// - virtualized ([ListView.builder]), newest at the bottom;
/// - an item's widget is reused until the item's `rev` changes, so a
///   streaming message rebuilds that message only;
/// - it follows the bottom only while the user is there; scrolled up, the
///   position stays and "Jump to latest" shows.
class AiTimeline extends StatefulWidget {
  const AiTimeline({super.key});

  /// Item widgets made (tests: the streaming bound).
  @visibleForTesting
  static int debugItemBuilds = 0;

  @override
  State<AiTimeline> createState() => _AiTimelineState();
}

final class _Built {
  _Built(this.rev, this.epoch, this.widget);
  final int rev;
  final int epoch;
  final Widget widget;
}

class _AiTimelineState extends State<AiTimeline> {
  final _scroll = ScrollController();
  final _cache = Expando<_Built>();

  /// Bumped when what every item reads changes (language, the scope).
  var _epoch = 0;
  var _stick = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _epoch++;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = _scroll.position;
    final atBottom = p.maxScrollExtent - p.pixels <= 24;
    if (atBottom != _stick) setState(() => _stick = atBottom);
  }

  void _followBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stick || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.position.pixels != max) _scroll.jumpTo(max);
    });
  }

  void _jumpToLatest() {
    setState(() => _stick = true);
    _followBottom();
  }

  Widget _item(TimelineItem item) {
    final hit = _cache[item];
    if (hit != null && hit.rev == item.rev && hit.epoch == _epoch) {
      return hit.widget;
    }
    AiTimeline.debugItemBuilds++;
    final widget = KeyedSubtree(
      key: ObjectKey(item),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AiSizes.column),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ShellxSpace.s16,
              vertical: ShellxSpace.s4,
            ),
            child: aiTimelineItem(item),
          ),
        ),
      ),
    );
    _cache[item] = _Built(item.rev, _epoch, widget);
    return widget;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: scope.frames,
      builder: (context, _) {
        final items = scope.state.timeline.items;
        if (_stick) _followBottom();
        return Stack(
          children: [
            Positioned.fill(
              // Item extents are estimated until laid out: a growing extent
              // moves the bottom, which a stuck view follows.
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  if (_stick) _followBottom();
                  return false;
                },
                child: ListView.builder(
                  key: const Key('ai.timeline'),
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    vertical: ShellxSpace.s16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _item(items[i]),
                ),
              ),
            ),
            if (!_stick)
              Positioned(
                left: 0,
                right: 0,
                bottom: ShellxSpace.s12,
                child: Center(
                  child: FilledButton.tonalIcon(
                    key: const Key('ai.jumpToLatest'),
                    onPressed: _jumpToLatest,
                    icon: const Icon(Icons.arrow_downward, size: 14),
                    label: Text(l10n.aiJumpToLatest),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The user's message: its text, its file mentions and images as chips.
class AiUserMessage extends StatelessWidget {
  const AiUserMessage({super.key, required this.item});
  final UserItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = [
      for (final b in item.blocks)
        if (b is TextBlock) b.text,
    ].join();
    final chips = [
      for (final b in item.blocks)
        if (b is ResourceLinkBlock)
          '@${b.name}'
        else if (b is ImageBlock)
          l10n.aiAttachImage,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiYou,
          style: ShellxText.caption.copyWith(
            color: ShellxDesktopColors.textSecondary,
          ),
        ),
        const SizedBox(height: ShellxSpace.s4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: ShellxSpace.s12,
            vertical: ShellxSpace.s8,
          ),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty)
                SelectableText(
                  text,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              if (chips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: ShellxSpace.s6),
                  child: Wrap(
                    spacing: ShellxSpace.s6,
                    runSpacing: ShellxSpace.s4,
                    children: [
                      for (final c in chips)
                        Chip(
                          label: Text(c, style: ShellxText.caption),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The agent's answer (`agent_message_chunk`, merged), as markdown.
class AiAgentText extends StatelessWidget {
  const AiAgentText({super.key, required this.item});
  final AgentTextItem item;

  @override
  Widget build(BuildContext context) =>
      SelectionArea(child: AiMarkdown(text: item.text));
}

/// A thought (`agent_thought_chunk`): folded; its text is built only once
/// opened (smoothness: collapsed bodies cost nothing).
class AiThought extends StatefulWidget {
  const AiThought({super.key, required this.item});
  final ThoughtItem item;

  @override
  State<AiThought> createState() => _AiThoughtState();
}

class _AiThoughtState extends State<AiThought> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const dim = ShellxDesktopColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(ShellxRadius.r4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _open ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: dim,
              ),
              Text(
                l10n.aiThinking,
                style: ShellxText.small.copyWith(color: dim),
              ),
            ],
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: ShellxSpace.s16),
            child: SelectableText(
              widget.item.text,
              style: ShellxText.small.copyWith(color: dim),
            ),
          ),
      ],
    );
  }
}

class _PlainLine extends StatelessWidget {
  const _PlainLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: ShellxText.small.copyWith(color: ShellxDesktopColors.textSecondary),
  );
}

/// Until the question cards (D22) land: the agent's question and a way to
/// say no, so a turn never waits on nothing.
class _AskFallback extends StatelessWidget {
  const _AskFallback({required this.item});
  final AskItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final runtime = AiPaneScope.of(context).runtime;
    return Row(
      children: [
        Expanded(child: _PlainLine(text: item.request.message)),
        if (item.response == null && !item.autoDeclined)
          TextButton(
            onPressed: () => runtime.answerAsk(item.id, const ElicitDecline()),
            child: Text(l10n.aiAskDecline),
          ),
      ],
    );
  }
}
