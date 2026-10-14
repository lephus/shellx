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
import 'ai_file_viewer.dart';
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
  final diffs = f.content?.whereType<ToolDiff>().toList() ?? const <ToolDiff>[];
  final loc = f.locations?.firstOrNull?.path;
  String rel(String? path) => path == null ? title : aiRelativePath(path, cwd);
  return switch (f.kind) {
    ToolKind.read => (verb: l10n.aiToolRead, target: rel(loc), mono: true),
    ToolKind.edit => (
      // A patch of several files: "a.ts, b.ts"; "Create" when all are new.
      verb: diffs.isNotEmpty && diffs.every((d) => d.oldText == null)
          ? l10n.aiToolCreate
          : l10n.aiToolEdit,
      target: diffs.length > 1
          ? diffs.map((d) => rel(d.path)).join(', ')
          : rel(diffs.firstOrNull?.path ?? loc),
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

/// A call's diffs, each computed once however often its card is built — a
/// card that scrolls out of the list and back in is a new State (smoothness:
/// a big diff is not diffed again): the lines, and the work in flight.
final _diffLines = Expando<List<DiffLine>>('tool diff');
final _diffRuns = Expando<Future<List<DiffLine>>>('tool diff run');

Future<List<DiffLine>> _diffOf(OffThread run, ToolDiff d) =>
    _diffRuns[d] ??= _compute(run, d);

Future<List<DiffLine>> _compute(OffThread run, ToolDiff d) {
  List<DiffLine> keep(List<DiffLine> lines) => _diffLines[d] = lines;
  try {
    return lineDiff(
      run,
      d.oldText ?? '',
      d.newText,
    ).then(keep, onError: (Object _) => keep(const []));
  } on Object {
    return SynchronousFuture(keep(const []));
  }
}

/// The escape sequences a terminal reads (colours, cursor moves, window
/// titles, character sets…); the card shows text. CSI, OSC (to BEL or ST),
/// then any other `ESC` + intermediates + final byte.
final _ansi = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)?|[ -/]*[0-~])',
);

/// [text] without terminal escape sequences (spec §4.2: output in the basic
/// colour).
String aiStripAnsi(String text) =>
    text.contains('\x1B') ? text.replaceAll(_ansi, '') : text;

/// Smoothness, and "capped outputs" is not negotiable: what a card shows of
/// one output — the start and the end of it — is about this many characters,
/// whatever the agent printed. What an agent writes has no length: some agents
/// and tools hand over megabytes.
const int kAiOutputMaxChars = 32 * 1024;

/// A shown line is cut here, with "…". Text with no place to break a line (a
/// base64 blob, a minified bundle, a run of `a`) costs a layout that grows
/// faster than its length: 1 MB on one line froze the window for 23 s.
const int kAiLineMaxChars = 2000;

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

/// The line `text[start, end)`, cut at [kAiLineMaxChars] characters with "…"
/// (never in the middle of a surrogate pair, which cannot be drawn).
String _lineOf(String text, int start, int end) {
  if (end - start <= kAiLineMaxChars) return text.substring(start, end);
  var cut = start + kAiLineMaxChars;
  if (_isHighSurrogate(text.codeUnitAt(cut - 1))) cut--;
  return '${text.substring(start, cut)}…';
}

/// [line], cut at [kAiLineMaxChars] characters with "…".
String aiCapLine(String line) => _lineOf(line, 0, line.length);

int _lineCount(String text) {
  var n = 1;
  for (var i = text.indexOf('\n'); i >= 0; i = text.indexOf('\n', i + 1)) {
    n++;
  }
  return n;
}

/// A long text as a card shows it: the first lines ([head]) and, when the
/// middle is left out, [hidden] lines and then the last ones ([tail]).
/// - Every line is cut at [kAiLineMaxChars] characters.
/// - [head] and [tail] keep at most [kAiOutputMaxChars] characters between
///   them, and at most the `endLines` the card was asked for each.
/// - The pieces are found by scanning from both ends: nothing of the middle
///   is copied, however long the text is.
final class AiOutput {
  AiOutput._(
    this.text, {
    required this.head,
    required this.tail,
    required this.hidden,
    required this.lines,
  });

  /// The whole text.
  final String text;
  final String head;

  /// Null: nothing is left out, [head] is all there is.
  final String? tail;

  /// How many lines are between [head] and [tail].
  final int hidden;

  /// How many lines [text] has.
  final int lines;

  bool get isEmpty => text.isEmpty;

  /// Every line of [text], for the "Show all" list: made when it is asked
  /// for, once. A row is cut with [aiCapLine] when it is drawn.
  late final List<String> allLines = text.split('\n');
}

/// [text] as [AiOutput]: at most [endLines] lines and half of
/// [kAiOutputMaxChars] characters from each end.
AiOutput aiOutputOf(String text, {int endLines = AiSizes.outputLines}) {
  const half = kAiOutputMaxChars ~/ 2;
  final total = _lineCount(text);
  final head = <String>[];
  var used = 0;
  for (var from = 0; head.length < endLines && head.length < total;) {
    final nl = text.indexOf('\n', from);
    final end = nl < 0 ? text.length : nl;
    final line = _lineOf(text, from, end);
    if (head.isNotEmpty && used + line.length + 1 > half) break;
    head.add(line);
    used += line.length + 1;
    from = end + 1;
  }
  final tail = <String>[];
  used = 0;
  for (
    var to = text.length;
    tail.length < endLines && head.length + tail.length < total;
  ) {
    final nl = to == 0 ? -1 : text.lastIndexOf('\n', to - 1);
    final line = _lineOf(text, nl + 1, to);
    if (tail.isNotEmpty && used + line.length + 1 > half) break;
    tail.add(line);
    used += line.length + 1;
    if (nl < 0) break;
    to = nl;
  }
  final hidden = total - head.length - tail.length;
  return hidden > 0
      ? AiOutput._(
          text,
          head: head.join('\n'),
          tail: tail.reversed.join('\n'),
          hidden: hidden,
          lines: total,
        )
      : AiOutput._(
          text,
          head: [...head, ...tail.reversed].join('\n'),
          tail: null,
          hidden: 0,
          lines: total,
        );
}

/// [text] in one piece for a place that has no "Show all" (the user's own
/// message, a long block of the agent's words, the agent's log): the same
/// caps as [aiOutputOf], and a line made by [marker] where the middle was
/// left out.
String aiCapText(String text, String Function(int hiddenLines) marker) {
  final out = aiOutputOf(text, endLines: 1 << 30);
  final tail = out.tail;
  return tail == null ? out.head : '${out.head}\n${marker(out.hidden)}\n$tail';
}

final _fenceOpen = RegExp(r'^(`{3,}|~{3,})[^`\n]*\n');

/// [text] without the one Markdown fence around it. claude-agent-acp sends a
/// command's result as "```console\n…\n```": the card shows the output, not
/// the fence lines (which would also count as lines). Text that is not
/// wrapped in one — or holds a line that would close the fence early — is
/// returned as it is.
String aiUnfence(String text) {
  final open = _fenceOpen.firstMatch(text);
  if (open == null) return text;
  final fence = open[1]!;
  final mark = fence.codeUnitAt(0);
  var end = text.length;
  while (end > open.end && _isSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  var run = 0;
  while (end - run > open.end && text.codeUnitAt(end - run - 1) == mark) {
    run++;
  }
  if (run < fence.length) return text;
  final close = end - run;
  // The closing fence is a line of its own.
  if (close > open.end && text.codeUnitAt(close - 1) != 0x0A) return text;
  final body = text.substring(open.end, close > open.end ? close - 1 : close);
  // A line in it that would close the fence: this was not one wrapper.
  if (body.contains(fence) &&
      RegExp('^${RegExp.escape(fence)}', multiLine: true).hasMatch(body)) {
    return text;
  }
  return body;
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x0A || unit == 0x0D || unit == 0x09;

/// The exit code a finished command reports, or null when the agent says
/// none. Codex gives it in `rawOutput` (`exit_code`), OpenCode in its
/// `metadata` (`exit`); Claude reports a failed command as the text
/// "Exit code N".
int? aiExitCode(Object? rawOutput) {
  if (rawOutput is String) {
    final m = RegExp(
      r'^\s*exit code:? (-?\d+)',
      caseSensitive: false,
    ).firstMatch(rawOutput);
    return m == null ? null : int.tryParse(m[1]!);
  }
  if (rawOutput is! Map) return null;
  for (final key in const [
    'exit_code',
    'exitCode',
    'exit',
    'returncode',
    'return_code',
  ]) {
    final v = rawOutput[key];
    if (v is int) return v;
    if (v is String) {
      final n = int.tryParse(v.trim());
      if (n != null) return n;
    }
  }
  for (final key in const ['metadata', 'result', 'output']) {
    final inner = rawOutput[key];
    if (inner is Map) {
      final code = aiExitCode(inner);
      if (code != null) return code;
    }
  }
  return null;
}

/// One tool call (spec §4.2, D10 notes under it). Smoothness: its body is
/// built only when open; long output shows its first and last
/// [AiSizes.outputLines] lines; a long diff runs off the UI isolate.
class AiToolCard extends ConsumerStatefulWidget {
  const AiToolCard({super.key, required this.item});
  final ToolItem item;

  /// Times an output was prepared for display (tests: once per revision of a
  /// call, however often its card is built).
  @visibleForTesting
  static int debugOutputPreps = 0;

  @override
  ConsumerState<AiToolCard> createState() => _AiToolCardState();
}

/// What a card shows of a call's text, made once per revision of the call (a
/// card that is built again, opened, or scrolled out of the list and back in
/// is not made again): the output without its fence and escape codes, cut;
/// and the arguments as JSON, cut.
final class _Shown {
  _Shown(this.content, this.rawInput, this.output);

  final List<ToolContent>? content;
  final Object? rawInput;
  final AiOutput output;

  late final AiOutput? input = rawInput == null
      ? null
      : aiOutputOf(const JsonEncoder.withIndent('  ').convert(rawInput));
}

final _shown = Expando<_Shown>('tool text');

_Shown _shownOf(ToolItem item) {
  final f = item.fields;
  final hit = _shown[item];
  if (hit != null &&
      identical(hit.content, f.content) &&
      identical(hit.rawInput, f.rawInput)) {
    return hit;
  }
  AiToolCard.debugOutputPreps++;
  return _shown[item] = _Shown(
    f.content,
    f.rawInput,
    aiOutputOf(
      aiStripAnsi(
        [
          for (final c in f.content ?? const <ToolContent>[])
            if (c case ToolContentBlock(block: TextBlock(:final text)))
              aiUnfence(text),
        ].join('\n'),
      ),
    ),
  );
}

class _AiToolCardState extends ConsumerState<AiToolCard> {
  /// Null: the automatic rule ([_autoOpen]).
  bool? _open;

  /// The diffs this card waits for (the others are done).
  final _watching = <ToolDiff>{};

  ToolItem get item => widget.item;

  /// Every file of the call (a patch has several).
  List<ToolDiff> get _toolDiffs => [
    for (final c in item.fields.content ?? const <ToolContent>[])
      if (c is ToolDiff) c,
  ];

  bool get _expandable => switch (item.fields.kind) {
    ToolKind.read || ToolKind.switchMode => false,
    _ => true,
  };

  /// Spec §4.2: an edit waiting for an answer, and a command that
  /// finished (failed too: its output and exit code are what to read, but not
  /// one that was refused: it ran nothing), open by themselves.
  bool get _autoOpen =>
      (item.awaitingPermission && item.fields.kind == ToolKind.edit) ||
      (item.fields.kind == ToolKind.execute &&
          (item.end == ToolEnd.completed ||
              (item.end == ToolEnd.failed &&
                  !(item.permissionAnswer?.kind.isReject ?? false))));

  bool get _isOpen => _expandable && (_open ?? _autoOpen);

  /// The viewer over the conversation (§4.2 "View whole file", `read`).
  void _view(String path, int? line) {
    final scope = AiPaneScope.of(context);
    scope.ui.showOverlay(
      AiFileViewer(
        key: UniqueKey(),
        path: aiRelativePath(path, scope.state.cwd),
        line: line,
      ),
    );
  }

  /// Starts the diffs not yet computed; a long one calls back when done.
  void _ensureDiffs(List<ToolDiff> diffs) {
    final run = ref.read(aiOffThreadProvider);
    for (final d in diffs) {
      final pending = _diffOf(run, d);
      if (_diffLines[d] != null || !_watching.add(d)) continue;
      unawaited(
        pending.then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = AiPaneScope.of(context).state;
    final diffs = _toolDiffs;
    _ensureDiffs(diffs);
    final label = aiToolLabel(l10n, item, state.cwd);
    if (item.fields.kind == ToolKind.switchMode) {
      return Text(
        label.target,
        style: ShellxText.small.copyWith(
          color: ShellxDesktopColors.textSecondary,
        ),
      );
    }
    // The lines of all the files, once all are there.
    final computed = [for (final d in diffs) ?_diffLines[d]];
    final stat = diffs.isEmpty || computed.length < diffs.length
        ? null
        : computed.map(diffStat).fold<DiffStat>(
            (added: 0, removed: 0),
            (sum, one) => (
              added: sum.added + one.added,
              removed: sum.removed + one.removed,
            ),
          );
    final asking = item.awaitingPermission;
    // §4.2: a `read` card opens the file at its line.
    final at = item.fields.kind == ToolKind.read
        ? item.fields.locations?.firstOrNull
        : null;
    final header = InkWell(
      onTap: _expandable
          ? () => setState(() => _open = !_isOpen)
          : at == null
          ? null
          : () => _view(at.path, at.line),
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
    // A Material, not a box: the header's hover and press paint on it, and a
    // background between the ink and the Material would hide them.
    return Material(
      color: ShellxDesktopColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        side: BorderSide(
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
    final diffs = _toolDiffs;
    final shown = _shownOf(item);
    final output = shown.output;
    final parts = <Widget>[];
    for (final (i, d) in diffs.indexed) {
      final lines = _diffLines[d];
      if (diffs.length > 1) parts.add(_FileName(aiRelativePath(d.path, cwd)));
      parts.add(
        lines == null
            ? const SizedBox(height: 17)
            : AiDiffView(lines: withContext(lines)),
      );
      parts.add(
        Wrap(
          spacing: ShellxSpace.s8,
          children: [
            TextButton.icon(
              key: Key(i == 0 ? 'ai.tool.view' : 'ai.tool.view.$i'),
              onPressed: () => _view(d.path, null),
              icon: const Icon(Icons.article_outlined, size: 14),
              label: Text(l10n.aiViewFile),
            ),
            TextButton.icon(
              key: Key(i == 0 ? 'ai.tool.editor' : 'ai.tool.editor.$i'),
              onPressed: () => unawaited(aiOpenInEditor(ref, d.path, cwd)),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: Text(l10n.aiOpenInEditor),
            ),
          ],
        ),
      );
    }
    final input = f.kind == ToolKind.other ? shown.input : null;
    if (input != null) {
      parts
        ..add(_Caption(l10n.aiToolInput))
        ..add(_Output(output: input));
      if (!output.isEmpty) parts.add(_Caption(l10n.aiToolResult));
    }
    final ended = f.kind == ToolKind.execute && item.end != null;
    if (!output.isEmpty && diffs.isEmpty) {
      parts.add(_Output(output: output));
    } else if (ended) {
      parts.add(
        Text(
          l10n.aiToolNoOutput,
          style: ShellxText.small.copyWith(
            color: ShellxDesktopColors.textSecondary,
          ),
        ),
      );
    }
    // Spec §4.2: a command that is done shows its exit code.
    final code = ended ? aiExitCode(f.rawOutput) : null;
    if (code != null) {
      parts.add(
        Padding(
          padding: const EdgeInsets.only(top: ShellxSpace.s4),
          child: Text(
            l10n.aiRunSheetFailed(code),
            key: const Key('ai.tool.exit'),
            style: ShellxText.caption.copyWith(
              color: code == 0
                  ? ShellxDesktopColors.textSecondary
                  : ShellxDesktopColors.err,
            ),
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

/// The file a diff of a several-file patch belongs to.
class _FileName extends StatelessWidget {
  const _FileName(this.path);
  final String path;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ShellxSpace.s6, bottom: ShellxSpace.s4),
    child: Text(
      path,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: kAiMono.copyWith(color: ShellxDesktopColors.textSecondary),
    ),
  );
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

/// "● running · 2.1 s": text that changes once a second, no animation, while
/// the pane is on screen.
class _Running extends StatelessWidget {
  const _Running({required this.item});
  final ToolItem item;

  @override
  Widget build(BuildContext context) => AiEverySecond(
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final took = DateTime.now().difference(item.startedAt);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 6, color: ShellxDesktopColors.accent),
          const SizedBox(width: ShellxSpace.s4),
          Text(
            l10n.aiToolRunning(aiSeconds(took, l10n.localeName)),
            key: const Key('ai.tool.status'),
            style: ShellxText.caption.copyWith(
              color: ShellxDesktopColors.accent,
            ),
          ),
        ],
      );
    },
  );
}

/// Tool output: the first and last [AiSizes.outputLines] lines — and at most
/// [kAiOutputMaxChars] characters of them, each line cut at
/// [kAiLineMaxChars] — "Show all" for the rest (smoothness: never thousands
/// of rows, never a megabyte of text at once).
class _Output extends StatefulWidget {
  const _Output({required this.output});
  final AiOutput output;

  @override
  State<_Output> createState() => _OutputState();
}

class _OutputState extends State<_Output> {
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final out = widget.output;
    const box = BoxDecoration(
      color: ShellxDesktopColors.surfaceInset,
      borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
    );
    if (_all) {
      final lines = out.allLines;
      return Container(
        height: 360,
        decoration: box,
        padding: const EdgeInsets.all(ShellxSpace.s6),
        child: ListView.builder(
          itemExtent: 17,
          itemCount: lines.length,
          itemBuilder: (context, i) => Text(
            aiCapLine(lines[i]),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: kAiMono,
          ),
        ),
      );
    }
    Widget block(String text) => SelectableText(text, style: kAiMono);
    return Container(
      decoration: box,
      padding: const EdgeInsets.all(ShellxSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          block(out.head),
          if (out.tail case final tail?) ...[
            Row(
              children: [
                Text(
                  l10n.aiOutputCut(out.hidden),
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
                const SizedBox(width: ShellxSpace.s8),
                TextButton(
                  key: const Key('ai.tool.showAll'),
                  onPressed: () => setState(() => _all = true),
                  child: Text(l10n.aiShowAllLines(out.lines)),
                ),
              ],
            ),
            block(tail),
          ],
        ],
      ),
    );
  }
}
