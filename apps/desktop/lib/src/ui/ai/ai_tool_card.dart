import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_off_thread.dart';
import '../../ai/line_diff.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_diff_view.dart';
import 'ai_editor.dart';
import 'ai_labels.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// What a tool card's header says (spec §4.2): a verb, its target, and
/// whether the target reads as code. The title is the merged one (V2-1a:
/// updates refine the generic first title).
({String verb, String target, bool mono}) aiToolLabel(
  AppLocalizations l10n,
  ToolItem item,
  String cwd,
) {
  final f = item.fields;
  final title = f.title ?? '';
  final diff = f.content?.whereType<ToolDiff>().firstOrNull;
  final loc = f.locations?.firstOrNull?.path;
  String rel(String? path) => path == null ? title : aiRelativePath(path, cwd);
  return switch (f.kind) {
    ToolKind.read => (verb: l10n.aiToolRead, target: rel(loc), mono: true),
    ToolKind.edit => (
      verb: diff != null && diff.oldText == null
          ? l10n.aiToolCreate
          : l10n.aiToolEdit,
      target: rel(diff?.path ?? loc),
      mono: true,
    ),
    ToolKind.delete => (verb: l10n.aiToolDelete, target: rel(loc), mono: true),
    ToolKind.move => (verb: l10n.aiToolMove, target: rel(loc), mono: true),
    ToolKind.search => (verb: l10n.aiToolSearch, target: title, mono: true),
    ToolKind.execute => (verb: l10n.aiToolExecute, target: title, mono: true),
    ToolKind.fetch => (verb: l10n.aiToolFetch, target: title, mono: false),
    ToolKind.think => (verb: l10n.aiThinking, target: title, mono: false),
    ToolKind.switchMode => (
      verb: '',
      target: l10n.aiToolModeChanged(title),
      mono: false,
    ),
    ToolKind.other || null => _mcp(title),
  };
}

/// `mcp__server__tool` reads "server · tool".
({String verb, String target, bool mono}) _mcp(String title) {
  final m = RegExp(r'^mcp__(.+?)__(.+)$').firstMatch(title);
  return m == null
      ? (verb: '', target: title, mono: false)
      : (verb: '', target: '${m[1]} · ${m[2]}', mono: true);
}

IconData _icon(ToolKind? kind) => switch (kind) {
  ToolKind.read => Icons.description_outlined,
  ToolKind.edit => Icons.edit_outlined,
  ToolKind.delete => Icons.delete_outline,
  ToolKind.move => Icons.drive_file_rename_outline,
  ToolKind.search => Icons.search,
  ToolKind.execute => Icons.terminal,
  ToolKind.fetch => Icons.cloud_download_outlined,
  ToolKind.think => Icons.psychology_outlined,
  ToolKind.switchMode => Icons.swap_horiz,
  ToolKind.other || null => Icons.extension_outlined,
};

/// One tool call (spec §4.2, D10 notes under it). Smoothness: its body is
/// built only when open; long output shows its first and last
/// [AiSizes.outputLines] lines; a long diff runs off the UI isolate.
class AiToolCard extends ConsumerStatefulWidget {
  const AiToolCard({super.key, required this.item});
  final ToolItem item;

  @override
  ConsumerState<AiToolCard> createState() => _AiToolCardState();
}

class _AiToolCardState extends ConsumerState<AiToolCard> {
  /// Null: the automatic rule ([_autoOpen]).
  bool? _open;
  ToolDiff? _diffOf;
  List<DiffLine>? _diff;

  ToolItem get item => widget.item;

  bool get _expandable => switch (item.fields.kind) {
    ToolKind.read || ToolKind.switchMode => false,
    _ => true,
  };

  /// Spec §4.2: an edit waiting for an answer, and a command that
  /// finished, open by themselves.
  bool get _autoOpen =>
      (item.awaitingPermission && item.fields.kind == ToolKind.edit) ||
      (item.fields.kind == ToolKind.execute && item.end == ToolEnd.completed);

  bool get _isOpen => _expandable && (_open ?? _autoOpen);

  void _ensureDiff() {
    final d = item.fields.content?.whereType<ToolDiff>().firstOrNull;
    if (d == null || identical(d, _diffOf)) return;
    _diffOf = d;
    _diff = null;
    final pending = lineDiff(
      ref.read(aiOffThreadProvider),
      d.oldText ?? '',
      d.newText,
    );
    if (pending is SynchronousFuture<List<DiffLine>>) {
      unawaited(pending.then((lines) => _diff = lines));
    } else {
      unawaited(
        pending.then((lines) {
          if (mounted && identical(_diffOf, d)) setState(() => _diff = lines);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = AiPaneScope.of(context).state;
    _ensureDiff();
    final label = aiToolLabel(l10n, item, state.cwd);
    if (item.fields.kind == ToolKind.switchMode) {
      return Text(
        label.target,
        style: ShellxText.small.copyWith(
          color: ShellxDesktopColors.textSecondary,
        ),
      );
    }
    final diff = _diff;
    final stat = diff == null ? null : diffStat(diff);
    final asking = item.awaitingPermission;
    final header = InkWell(
      onTap: _expandable ? () => setState(() => _open = !_isOpen) : null,
      borderRadius: BorderRadius.circular(ShellxRadius.r8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShellxSpace.s8,
          vertical: ShellxSpace.s6,
        ),
        child: Row(
          children: [
            Icon(
              _icon(item.fields.kind),
              size: 14,
              color: ShellxDesktopColors.textSecondary,
            ),
            const SizedBox(width: ShellxSpace.s6),
            if (label.verb.isNotEmpty) ...[
              Text(
                label.verb,
                style: ShellxText.bodyStrong.copyWith(
                  color: ShellxDesktopColors.textPrimary,
                ),
              ),
              const SizedBox(width: ShellxSpace.s6),
            ],
            Expanded(
              child: Text(
                label.target,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: label.mono
                    ? kAiMono
                    : ShellxText.body.copyWith(
                        color: ShellxDesktopColors.textPrimary,
                      ),
              ),
            ),
            if (stat != null) ...[
              Text(
                '+${stat.added}',
                style: kAiMono.copyWith(color: ShellxDesktopColors.ok),
              ),
              const SizedBox(width: ShellxSpace.s4),
              Text(
                '−${stat.removed}',
                style: kAiMono.copyWith(color: ShellxDesktopColors.err),
              ),
              const SizedBox(width: ShellxSpace.s8),
            ],
            _Status(item: item),
            if (_expandable)
              Icon(
                _isOpen ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: ShellxDesktopColors.textSecondary,
              ),
          ],
        ),
      ),
    );
    final note = _permissionNote(l10n, state);
    return Container(
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surface,
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        border: Border.all(
          color: asking
              ? ShellxDesktopColors.warnBorder
              : ShellxDesktopColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (_isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ShellxSpace.s8,
                0,
                ShellxSpace.s8,
                ShellxSpace.s8,
              ),
              child: _body(l10n, state.cwd),
            ),
          ?note,
        ],
      ),
    );
  }

  Widget _body(AppLocalizations l10n, String cwd) {
    final f = item.fields;
    final d = _diffOf;
    final output = [
      for (final c in f.content ?? const <ToolContent>[])
        if (c case ToolContentBlock(block: TextBlock(:final text))) text,
    ].join('\n');
    final parts = <Widget>[];
    if (d != null) {
      final diff = _diff;
      parts.add(
        diff == null
            ? const SizedBox(height: 17)
            : AiDiffView(lines: withContext(diff)),
      );
      parts.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('ai.tool.editor'),
            onPressed: () => unawaited(aiOpenInEditor(ref, d.path, cwd)),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: Text(l10n.aiOpenInEditor),
          ),
        ),
      );
    }
    if (f.kind == ToolKind.other && f.rawInput != null) {
      parts
        ..add(_Caption(l10n.aiToolInput))
        ..add(
          _Output(text: const JsonEncoder.withIndent('  ').convert(f.rawInput)),
        );
      if (output.isNotEmpty) parts.add(_Caption(l10n.aiToolResult));
    }
    if (output.isNotEmpty && d == null) {
      parts.add(_Output(text: output));
    } else if (f.kind == ToolKind.execute && item.end != null) {
      parts.add(
        Text(
          l10n.aiToolNoOutput,
          style: ShellxText.small.copyWith(
            color: ShellxDesktopColors.textSecondary,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: parts,
    );
  }

  /// D10 under the card: how to answer, or what was chosen.
  Widget? _permissionNote(AppLocalizations l10n, AiSessionState state) {
    Widget note(IconData icon, Color color, String text) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ShellxSpace.s8,
        vertical: ShellxSpace.s6,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ShellxDesktopColors.line)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: ShellxSpace.s6),
          Expanded(
            child: Text(text, style: ShellxText.small.copyWith(color: color)),
          ),
        ],
      ),
    );
    if (item.awaitingPermission) {
      final n =
          state.permissions
              .where((p) => identical(p.item, item))
              .firstOrNull
              ?.request
              .options
              .length ??
          0;
      return note(
        Icons.warning_amber_rounded,
        ShellxDesktopColors.warn,
        l10n.aiPermWaiting(n),
      );
    }
    final answer = item.permissionAnswer;
    if (answer != null) {
      final no = answer.kind.isReject;
      return note(
        no ? Icons.close : Icons.check,
        no ? ShellxDesktopColors.err : ShellxDesktopColors.ok,
        l10n.aiPermChosen(aiPermissionLabel(l10n, answer), answer.name),
      );
    }
    if (item.permissionCancelled) {
      return note(
        Icons.stop_circle_outlined,
        ShellxDesktopColors.textSecondary,
        l10n.aiPermCancelled,
      );
    }
    return null;
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ShellxSpace.s6, bottom: ShellxSpace.s4),
    child: Text(
      text,
      style: ShellxText.caption.copyWith(
        color: ShellxDesktopColors.textSecondary,
      ),
    ),
  );
}

/// The card's status (spec §4.2): text, never a looping animation.
class _Status extends StatelessWidget {
  const _Status({required this.item});
  final ToolItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget text(String s, Color c) => Text(
      s,
      key: const Key('ai.tool.status'),
      style: ShellxText.caption.copyWith(color: c),
    );
    if (item.awaitingPermission) {
      return text(l10n.aiToolAwaiting, ShellxDesktopColors.warn);
    }
    switch (item.end) {
      case ToolEnd.completed:
        final ended = item.endedAt;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check,
              size: 14,
              color: ShellxDesktopColors.ok,
              semanticLabel: l10n.aiToolDone,
            ),
            if (item.fields.kind == ToolKind.execute && ended != null)
              text(
                l10n.aiToolTook(
                  aiSeconds(ended.difference(item.startedAt), l10n.localeName),
                ),
                ShellxDesktopColors.textSecondary,
              ),
          ],
        );
      case ToolEnd.failed:
        final rejected = item.permissionAnswer?.kind.isReject ?? false;
        return text(
          rejected ? l10n.aiToolRejected : l10n.aiToolFailed,
          ShellxDesktopColors.err,
        );
      case ToolEnd.stopped:
        return text(l10n.aiToolStopped, ShellxDesktopColors.textSecondary);
      case null:
        return item.fields.status == ToolCallStatus.inProgress
            ? _Running(item: item)
            : text(l10n.aiToolPending, ShellxDesktopColors.textSecondary);
    }
  }
}

/// "● running · 2.1 s": text that changes once a second, no animation.
class _Running extends StatefulWidget {
  const _Running({required this.item});
  final ToolItem item;

  @override
  State<_Running> createState() => _RunningState();
}

class _RunningState extends State<_Running> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final took = DateTime.now().difference(widget.item.startedAt);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.circle, size: 6, color: ShellxDesktopColors.accent),
        const SizedBox(width: ShellxSpace.s4),
        Text(
          l10n.aiToolRunning(aiSeconds(took, l10n.localeName)),
          key: const Key('ai.tool.status'),
          style: ShellxText.caption.copyWith(color: ShellxDesktopColors.accent),
        ),
      ],
    );
  }
}

/// Tool output: the first and last [AiSizes.outputLines] lines, "Show all"
/// for the rest (smoothness: never thousands of rows at once).
class _Output extends StatefulWidget {
  const _Output({required this.text});
  final String text;

  @override
  State<_Output> createState() => _OutputState();
}

class _OutputState extends State<_Output> {
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lines = widget.text.split('\n');
    const n = AiSizes.outputLines;
    const box = BoxDecoration(
      color: ShellxDesktopColors.surfaceInset,
      borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
    );
    if (_all) {
      return Container(
        height: 360,
        decoration: box,
        padding: const EdgeInsets.all(ShellxSpace.s6),
        child: ListView.builder(
          itemExtent: 17,
          itemCount: lines.length,
          itemBuilder: (context, i) => Text(
            lines[i],
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: kAiMono,
          ),
        ),
      );
    }
    final cut = lines.length > 2 * n;
    Widget block(Iterable<String> ls) =>
        SelectableText(ls.join('\n'), style: kAiMono);
    return Container(
      decoration: box,
      padding: const EdgeInsets.all(ShellxSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          block(cut ? lines.take(n) : lines),
          if (cut) ...[
            Row(
              children: [
                Text(
                  l10n.aiOutputCut(lines.length - 2 * n),
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
                const SizedBox(width: ShellxSpace.s8),
                TextButton(
                  key: const Key('ai.tool.showAll'),
                  onPressed: () => setState(() => _all = true),
                  child: Text(l10n.aiShowAllLines(lines.length)),
                ),
              ],
            ),
            block(lines.skip(lines.length - n)),
          ],
        ],
      ),
    );
  }
}
