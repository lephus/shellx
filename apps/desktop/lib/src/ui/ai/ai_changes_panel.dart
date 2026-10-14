import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_diff_overlay.dart';
import 'ai_notice_card.dart' show aiUndoReason;
import 'ai_scope.dart';

/// "This turn" or "Whole session" (§4.4).
enum AiChangesScope { turn, session }

/// The session's turns that have a restore point: the first, the last (the
/// running one counts), the last finished one; and whether a turn runs.
typedef AiTurns = ({int? first, int? last, int? lastFinished, bool running});

AiTurns aiTurnsOf(AiSessionState s) {
  int? first, last, lastFinished;
  for (final item in s.timeline.items) {
    if (item is TurnEndItem && item.checkpoint != null) {
      first ??= item.turn;
      last = item.turn;
      lastFinished = item.turn;
    }
  }
  final running = s.turn;
  if (running != null && running.checkpoint != null) {
    first ??= running.index;
    last = running.index;
  }
  return (
    first: first,
    last: last,
    lastFinished: lastFinished,
    running: running != null,
  );
}

/// The last turn that ended — with a restore point or without one (undo
/// off, a snapshot that failed) — or null. What the Files panel and `@` read
/// the project again after (D18); [aiTurnsOf] counts only turns that have a
/// restore point, so with undo off it would never move.
int? aiLastEndedTurn(AiSessionState s) {
  final items = s.timeline.items;
  for (var i = items.length - 1; i >= 0; i--) {
    final item = items[i];
    if (item is TurnEndItem) return item.turn;
  }
  return null;
}

/// Why undo is off right now: the latest "undo is off" card of the
/// conversation that is still open; null when undo works.
UndoUnavailable? aiUndoOffOf(AiSessionState s) {
  final items = s.timeline.items;
  for (var i = items.length - 1; i >= 0; i--) {
    final item = items[i];
    if (item is! NoticeItem || item.resolved) continue;
    final notice = item.notice;
    if (notice is UndoUnavailable) return notice;
  }
  return null;
}

/// B14: what the undo dialog chose.
enum AiRevertChoice { onlyUnchanged, all }

/// B14, §4.4: "Some files changed after this turn" — Cancel (the first
/// focus) / Only revert unchanged files / Revert all (destructive). The
/// middle choice shows only when some files are unchanged.
Future<AiRevertChoice?> showAiRevertDialog(
  BuildContext context, {
  required List<String> touched,
  required bool someUnchanged,
}) => showDialog<AiRevertChoice>(
  context: context,
  builder: (context) {
    final l10n = AppLocalizations.of(context);
    final names = touched.length <= 3
        ? touched.join(', ')
        : '${touched.take(3).join(', ')}…';
    return AlertDialog(
      title: Text(l10n.aiRevertDialogTitle),
      content: Text(l10n.aiRevertDialogBody(names)),
      actions: [
        TextButton(
          key: const Key('ai.revert.cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        if (someUnchanged)
          OutlinedButton(
            key: const Key('ai.revert.clean'),
            onPressed: () =>
                Navigator.of(context).pop(AiRevertChoice.onlyUnchanged),
            child: Text(l10n.aiRevertOnlyClean),
          ),
        FilledButton(
          key: const Key('ai.revert.all'),
          style: destructiveButtonStyle(),
          onPressed: () => Navigator.of(context).pop(AiRevertChoice.all),
          child: Text(l10n.aiRevertAll),
        ),
      ],
    );
  },
);

/// "Revert turn" [turn], "Revert session" ([turn] null), or one file
/// ([only]), §4.4: the files changed since the restore point go back. Files
/// changed after the turn ended ask first (B14). Refused while a turn runs.
/// The result shows at the foot of the Changes panel, which opens.
Future<void> aiRevert(
  BuildContext context,
  AiRuntime runtime,
  AiPaneUi ui, {
  int? turn,
  String? only,
}) async {
  final l10n = AppLocalizations.of(context);
  ui.openPanel();
  if (runtime.state.turn != null) {
    ui.note.value = l10n.aiRevertBusy;
    return;
  }
  final last = turn ?? aiTurnsOf(runtime.state).lastFinished;
  final changes = turn == null
      ? await runtime.sessionChanges()
      : await runtime.changesSince(turn);
  if (changes == null) {
    // git did not answer: said, never a silent nothing.
    ui.note.value = l10n.aiRevertFailed;
    return;
  }
  var paths = [
    for (final c in changes)
      if (only == null || c.path == only) c.path,
  ];
  if (paths.isEmpty) {
    // Nothing of it is changed any more (put back by hand): the panel
    // looks again, so the row it still shows goes.
    ui.changesChanged();
    return;
  }
  // A turn that ended without its end tree (the agent died, "Dừng hẳn")
  // cannot say what changed after it: any file may have, so every file asks.
  final known = last == null
      ? const <String>{}
      : await runtime.changedAfterTurn(last);
  final after = known ?? paths.toSet();
  final touched = [
    for (final path in paths)
      if (after.contains(path)) path,
  ];
  if (touched.isNotEmpty) {
    if (!context.mounted) return;
    final choice = await showAiRevertDialog(
      context,
      touched: touched,
      someUnchanged: touched.length < paths.length,
    );
    if (choice == null) return;
    if (choice == AiRevertChoice.onlyUnchanged) {
      paths = [
        for (final path in paths)
          if (!after.contains(path)) path,
      ];
    }
  }
  var ok = false;
  try {
    ok = turn == null
        ? await runtime.revertSession(paths)
        : await runtime.revert(turn, paths);
  } on Object catch (error) {
    debugPrint('ShellX: revert failed: ${error.runtimeType}');
  }
  ui.note.value = ok
      ? l10n.aiReverted(paths.length)
      // A turn started while the dialog was open: that is the reason.
      : runtime.state.turn != null
      ? l10n.aiRevertBusy
      : l10n.aiRevertFailed;
  ui.changesChanged();
}

/// "Reviewed" (§4.4) belongs to a file as it is: a change with other
/// counts is another review (ruling B16).
String aiReviewKey(FileChange c) =>
    '${c.path}\u0000${c.kind.name}\u0000${c.added}\u0000${c.removed}';

/// The Changes tab (spec §4.4): this turn's or the whole session's files,
/// each with M/A/D, its folder dimmed, +/−, "Reviewed", "Revert this file"
/// and "changed after the turn"; the restore point and "Revert turn" /
/// "Revert session" at the foot. A row opens its diff over the
/// conversation. It reloads when a turn starts or ends and after a revert.
class AiChangesPanel extends StatefulWidget {
  const AiChangesPanel({super.key});

  @override
  State<AiChangesPanel> createState() => _AiChangesPanelState();
}

class _AiChangesPanelState extends State<AiChangesPanel> {
  var _scope = AiChangesScope.turn;
  AiPaneScope? _pane;
  AiTurns? _turns;

  /// Why undo is off, while no turn has a restore point to show.
  UndoUnavailable? _undoOff;
  List<FileChange>? _changes;
  Set<String> _after = const {};
  var _loaded = false;
  var _gen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pane = AiPaneScope.of(context);
    if (!identical(pane.frames, _pane?.frames)) {
      _pane?.frames.removeListener(_onFrame);
      _pane?.ui.changes.removeListener(_reload);
      pane.frames.addListener(_onFrame);
      pane.ui.changes.addListener(_reload);
      _pane = pane;
      _turns = aiTurnsOf(pane.state);
      _undoOff = _undoOffOf(_turns!, pane.state);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    _pane = pane;
  }

  @override
  void dispose() {
    _pane?.frames.removeListener(_onFrame);
    _pane?.ui.changes.removeListener(_reload);
    // The note is about what was done here; it does not wait for the panel
    // to open again.
    _clearNote();
    super.dispose();
  }

  UndoUnavailable? _undoOffOf(AiTurns turns, AiSessionState state) =>
      turns.last == null ? aiUndoOffOf(state) : null;

  /// A result ("Reverted 2 files.", "Wait for the running turn to finish.")
  /// that is no longer true: a turn started or ended, the scope changed.
  void _clearNote() {
    final note = _pane?.ui.note;
    if (note != null && note.value != null) note.value = null;
  }

  void _onFrame() {
    final state = _pane!.state;
    final next = aiTurnsOf(state);
    final off = _undoOffOf(next, state);
    if (next == _turns) {
      if (!identical(off, _undoOff)) setState(() => _undoOff = off);
      return;
    }
    _turns = next;
    _undoOff = off;
    _clearNote();
    unawaited(_load());
  }

  void _reload() => unawaited(_load());

  int? get _turn =>
      _scope == AiChangesScope.turn ? _turns?.last : _turns?.first;

  Future<void> _load() async {
    final gen = ++_gen;
    final pane = _pane!;
    final turns = _turns!;
    final turn = _turn;
    if (turn == null) {
      setState(() {
        _loaded = true;
        _changes = null;
        _after = const {};
      });
      return;
    }
    final runtime = pane.runtime;
    final changes = _scope == AiChangesScope.turn
        ? await runtime.changesSince(turn)
        : await runtime.sessionChanges();
    final last = _scope == AiChangesScope.turn ? turn : turns.lastFinished;
    final after = last == null ? null : await runtime.changedAfterTurn(last);
    if (!mounted || gen != _gen) return;
    setState(() {
      _loaded = true;
      _changes = changes;
      _after = after ?? const {};
    });
  }

  void _open(FileChange c) {
    final pane = _pane!;
    final turn = _turn;
    if (turn == null) return;
    pane.ui.showOverlay(
      AiDiffOverlay(
        key: ValueKey('ai.diff.${c.path}'),
        path: c.path,
        turn: turn,
        session: _scope == AiChangesScope.session,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = _pane!;
    final turns = _turns!;
    final turn = _turn;
    final changes = _changes;
    final dim = ShellxText.caption.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    Widget line(String text) => Padding(
      padding: const EdgeInsets.all(ShellxSpace.s12),
      child: Text(text, style: dim),
    );
    final Widget body;
    if (!_loaded) {
      body = const SizedBox.shrink();
    } else if (turn == null) {
      // No turn has a restore point: none yet, or undo is off and says why.
      final off = _undoOff;
      body = line(
        off == null
            ? l10n.aiChangesNoTurn
            : off.turnOnly
            ? l10n.aiNoUndoTurn(aiUndoReason(l10n, off.reason))
            : l10n.aiNoUndo(aiUndoReason(l10n, off.reason)),
      );
    } else if (changes == null) {
      // The turn is there; git did not answer.
      body = line(l10n.errorUnexpected('changes'));
    } else if (changes.isEmpty) {
      body = line(l10n.aiChangesEmpty);
    } else {
      body = ListView.builder(
        itemCount: changes.length,
        itemBuilder: (context, i) {
          final c = changes[i];
          final key = aiReviewKey(c);
          return _ChangeRow(
            key: ValueKey('ai.change.${c.path}'),
            change: c,
            after: _after.contains(c.path),
            reviewed: pane.ui.reviewed.contains(key),
            onOpen: () => _open(c),
            onReviewed: (on) => setState(
              () =>
                  on ? pane.ui.reviewed.add(key) : pane.ui.reviewed.remove(key),
            ),
            onRevert: () => unawaited(
              aiRevert(
                context,
                pane.runtime,
                pane.ui,
                turn: _scope == AiChangesScope.turn ? turn : null,
                only: c.path,
              ),
            ),
          );
        },
      );
    }
    final checkpoint = turn == null ? null : pane.runtime.checkpointOf(turn);
    final canRevert =
        !turns.running && checkpoint != null && (changes?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(ShellxSpace.s8),
          child: SegmentedButton<AiChangesScope>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: AiChangesScope.turn,
                label: Text(
                  l10n.aiScopeTurn,
                  key: const Key('ai.changes.turn'),
                ),
              ),
              ButtonSegment(
                value: AiChangesScope.session,
                label: Text(
                  l10n.aiScopeSession,
                  key: const Key('ai.changes.session'),
                ),
              ),
            ],
            selected: {_scope},
            onSelectionChanged: (s) {
              _clearNote();
              setState(() => _scope = s.single);
              unawaited(_load());
            },
          ),
        ),
        Expanded(child: body),
        const Divider(height: 1, color: ShellxDesktopColors.line),
        Padding(
          padding: const EdgeInsets.all(ShellxSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (turn != null && checkpoint != null)
                Text(
                  l10n.aiCheckpoint(
                    turn,
                    checkpoint.commit.length > 7
                        ? checkpoint.commit.substring(0, 7)
                        : checkpoint.commit,
                  ),
                  key: const Key('ai.changes.checkpoint'),
                  style: dim,
                ),
              const SizedBox(height: ShellxSpace.s4),
              OutlinedButton.icon(
                key: const Key('ai.changes.revert'),
                onPressed: canRevert
                    ? () => unawaited(
                        aiRevert(
                          context,
                          pane.runtime,
                          pane.ui,
                          turn: _scope == AiChangesScope.turn ? turn : null,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.undo, size: 14),
                label: Text(
                  _scope == AiChangesScope.turn
                      ? l10n.aiRevertTurn
                      : l10n.aiRevertSession,
                ),
              ),
              if (turns.running)
                Text(
                  l10n.aiRevertBusy,
                  style: dim.copyWith(color: ShellxDesktopColors.warn),
                ),
              ValueListenableBuilder<String?>(
                valueListenable: pane.ui.note,
                builder: (context, note, _) => note == null
                    ? const SizedBox.shrink()
                    : Semantics(
                        liveRegion: true,
                        child: Text(
                          note,
                          key: const Key('ai.changes.note'),
                          style: ShellxText.small.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: ShellxSpace.s4),
              Text(l10n.aiIgnoredNote, style: dim),
              Text(l10n.aiOutsideNote, style: dim),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    super.key,
    required this.change,
    required this.after,
    required this.reviewed,
    required this.onOpen,
    required this.onReviewed,
    required this.onRevert,
  });

  final FileChange change;
  final bool after;
  final bool reviewed;
  final VoidCallback onOpen;
  final ValueChanged<bool> onReviewed;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = change;
    final (letter, color) = switch (c.kind) {
      ChangeKind.added => ('A', ShellxDesktopColors.ok),
      ChangeKind.modified => ('M', ShellxDesktopColors.warn),
      ChangeKind.deleted => ('D', ShellxDesktopColors.err),
    };
    final slash = c.path.lastIndexOf('/');
    final dir = slash < 0 ? '' : c.path.substring(0, slash + 1);
    final name = c.path.substring(slash + 1);
    final small = ShellxText.small;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShellxSpace.s8,
          vertical: ShellxSpace.s2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Text(letter, style: small.copyWith(color: color)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: dir,
                          style: small.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                        TextSpan(
                          text: name,
                          style: small.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (after)
                    Text(
                      l10n.aiChangedAfterTurn,
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.warn,
                      ),
                    ),
                ],
              ),
            ),
            if (c.binary)
              Text(
                l10n.aiBinaryFile,
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              )
            else ...[
              Text(
                '+${c.added}',
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.ok,
                ),
              ),
              const SizedBox(width: ShellxSpace.s4),
              Text(
                '−${c.removed}',
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
            ],
            Tooltip(
              message: l10n.aiReviewed,
              child: Checkbox(
                visualDensity: VisualDensity.compact,
                value: reviewed,
                onChanged: (on) => onReviewed(on ?? false),
              ),
            ),
            IconButton(
              tooltip: l10n.aiRevertFile,
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              onPressed: onRevert,
              icon: const Icon(Icons.undo),
            ),
          ],
        ),
      ),
    );
  }
}
