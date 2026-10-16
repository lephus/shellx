import 'dart:async';

import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_revert_outcome.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// How long the buttons of a revert question ignore taps after it appears (V2-2 §13, B20): the tap that opened it
/// must not answer it too.
const Duration _kSettle = Duration(milliseconds: 400);

/// The most files a revert question lists; "and N more" says the rest.
const int _kListed = 8;

/// V2-2b B20: "Thay đổi" — the files a turn changed ([turn]; null: the whole session, "Cả phiên"), each one opening
/// its diff ([onOpenFile]), and the revert at the foot: red, dim while a turn runs, and asked first, with the files
/// (B19). From a turn's summary it opens on that turn; from the menu on the whole session, and "Lượt này" is then the
/// last turn with a restore point.
Future<void> showAiChangesSheet(
  BuildContext context,
  AiSessionController controller, {
  int? turn,
  required void Function(String path, int? turn) onOpenFile,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: context.colors.surface,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
  builder: (context) => AiChangesSheet(controller: controller, turn: turn, onOpenFile: onOpenFile),
);

class AiChangesSheet extends StatefulWidget {
  const AiChangesSheet({super.key, required this.controller, required this.onOpenFile, this.turn});

  final AiSessionController controller;
  final int? turn;
  final void Function(String path, int? turn) onOpenFile;

  @override
  State<AiChangesSheet> createState() => _AiChangesSheetState();
}

class _AiChangesSheetState extends State<AiChangesSheet> {
  /// The turn of "Lượt này": the one asked for, else the last with a restore point (the first answer says it).
  late int? _turn = widget.turn;

  /// "Lượt này" (true) or "Cả phiên" (false).
  late bool _thisTurn = widget.turn != null;
  AiChangesView? _view;
  String? _error;
  var _loading = true;
  var _asked = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Reads the changes of the scope shown; a newer read wins over an older one still on its way. The view read, or
  /// null when the read failed (the sheet says why) or a newer one took its place.
  Future<AiChangesView?> _load() async {
    final asked = ++_asked;
    if (mounted && !_loading) setState(() => _loading = true);
    final result = await widget.controller.loadChanges(turn: _thisTurn ? _turn : null);
    if (!mounted || asked != _asked) return null;
    setState(() {
      _loading = false;
      _view = result.view;
      _error = result.code == null ? null : AiWords.failure(S.of(context), result.code!) ?? S.of(context).aiRefused;
      _turn ??= result.view?.last;
    });
    return result.view;
  }

  void _scope(bool thisTurn) {
    if (thisTurn == _thisTurn) return;
    setState(() => _thisTurn = thisTurn);
    unawaited(_load());
  }

  /// One revert of the scope shown, asked first on the phone with the files it puts back as the tap reads them (F51):
  /// a turn that ran while the sheet was open may have changed more than the sheet showed, and the computer asks again
  /// only about files changed after the turn. A read that fails, or finds nothing to put back, asks nothing and sends
  /// nothing: the sheet says so. When the computer asks too (files changed after the turn), its question with the
  /// desktop's choices (B14). Never sent again by itself.
  Future<void> _revert() async {
    final controller = widget.controller;
    final s = S.of(context);
    final turn = _thisTurn ? _turn : null;
    final view = await _load();
    if (view == null || view.files.isEmpty || !mounted) return;
    final sure = await showAiRevertConfirm(
      context,
      paths: [for (final f in view.files) f.path],
      more: view.more,
      turn: turn,
    );
    if (!sure || !mounted) return;
    var outcome = await controller.revert(turn: turn);
    if (outcome case AiRevertAsk(:final question)) {
      if (!mounted) return;
      final keep = await showAiRevertTouched(context, question);
      if (keep == null || !mounted) return;
      outcome = await controller.revert(turn: turn, keep: keep);
    }
    switch (outcome) {
      case AiRevertDone(:final count):
        controller.popupHandler.showSuccess(title: s.aiReverted(count));
      case AiRevertFailed(:final code):
        final text = AiWords.failure(s, code);
        if (text != null) controller.popupHandler.showError(title: text);
      case AiRevertAsk():
        // Asked again although the phone said what to keep: nothing went back.
        controller.popupHandler.showError(title: s.aiRequestFailed('confirm'));
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const Key('ai.changes.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.aiChanges, style: context.typo.heading20.heavy),
            12.sizedHeight,
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: true,
                  enabled: _turn != null,
                  label: Text(s.aiThisTurn, key: const Key('ai.changes.turn')),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(s.aiWholeSession, key: const Key('ai.changes.session')),
                ),
              ],
              selected: {_thisTurn},
              onSelectionChanged: (choice) => _scope(choice.single),
            ),
            12.sizedHeight,
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: _body(context),
            ),
            12.sizedHeight,
            Watch(_foot),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final dim = context.typo.paragraph13.copyWith(color: colors.secondaryText);
    final view = _view;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (view == null) {
      return Text(_error ?? s.aiRefused, key: const Key('ai.changes.error'), style: dim);
    }
    if (view.files.isEmpty) {
      final why = AiWords.undoReason(s, view.off);
      return Text(
        view.off == null
            ? s.aiChangesEmpty
            : why == null
            ? s.aiNoticeUndoOff
            : s.aiNoticeUndoOffReason(why),
        key: Key(view.off == null ? 'ai.changes.empty' : 'ai.changes.off'),
        style: dim,
      );
    }
    final after = view.after.toSet();
    return ListView(
      shrinkWrap: true,
      children: [
        for (final f in view.files)
          _FileRow(
            key: ValueKey('ai.change.${f.path}'),
            file: f,
            after: after.contains(f.path),
            onTap: () => widget.onOpenFile(f.path, _thisTurn ? _turn : null),
          ),
        if (view.more > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.aiChangesMore(view.more), key: const Key('ai.changes.more'), style: dim),
          ),
      ],
    );
  }

  /// The revert: red, for the scope shown; dim and waiting while a turn runs on the computer (B20), or while one is
  /// on its way.
  Widget _foot(BuildContext context) {
    final controller = widget.controller;
    controller.version.value; // a turn that starts or ends
    final reverting = controller.reverting.value;
    final s = S.of(context);
    final colors = context.colors;
    final view = _view;
    final turn = _thisTurn ? _turn : null;
    final running = controller.head?.running ?? false;
    final files = view?.files ?? const <AiChangedFile>[];
    final enabled =
        controller.can(AiFeature.revert) &&
        controller.linkState == AiLinkState.live &&
        !_loading &&
        files.isNotEmpty &&
        !running &&
        !reverting;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: const Key('ai.changes.revert'),
          style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.white),
          onPressed: enabled ? () => unawaited(_revert()) : null,
          child: Text(turn == null ? s.aiRevertSession : s.aiRevertTurn),
        ),
        if (running) ...[
          6.sizedHeight,
          Text(
            s.aiRevertBusy,
            key: const Key('ai.changes.busy'),
            textAlign: TextAlign.center,
            style: context.typo.paragraph13.copyWith(color: colors.warn),
          ),
        ],
      ],
    );
  }
}

/// One changed file: A/M/D, its folder dimmed and its name, "+3 −1" (or "nhị phân"), and whether it changed again
/// after the turn.
class _FileRow extends StatelessWidget {
  const _FileRow({super.key, required this.file, required this.after, required this.onTap});

  final AiChangedFile file;
  final bool after;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final f = file;
    final (letter, color) = switch (f.kind) {
      'a' => ('A', colors.ok),
      'd' => ('D', colors.error),
      _ => ('M', colors.warn),
    };
    final slash = f.path.lastIndexOf('/');
    final dir = slash < 0 ? '' : f.path.substring(0, slash + 1);
    final name = f.path.substring(slash + 1);
    final small = context.typo.paragraph13;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(letter, style: small.bold.copyWith(color: color)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: dir,
                          style: small.copyWith(color: colors.secondaryText),
                        ),
                        TextSpan(
                          text: name,
                          style: small.copyWith(color: colors.primaryText),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (after) Text(s.aiChangedAfter, style: context.typo.metadata12.copyWith(color: colors.warn)),
                ],
              ),
            ),
            8.sizedWidth,
            Text(
              f.binary ? s.aiBinaryFile : '+${f.plus} −${f.minus}',
              style: context.typo.metadata12.copyWith(color: colors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

/// V2-2b B20: "Revert 2 files to before turn 3?" with the files, Cancel and the red revert. Its buttons wait 400 ms
/// before they answer. True: revert.
Future<bool> showAiRevertConfirm(
  BuildContext context, {
  required List<String> paths,
  int more = 0,
  int? turn,
}) async {
  final s = S.of(context);
  final count = paths.length + more;
  final chosen = await showDialog<String>(
    context: context,
    builder: (context) => _SettledQuestion(
      key: const Key('ai.revert.dialog'),
      title: turn == null ? s.aiRevertConfirmSession(count) : s.aiRevertConfirm(count, turn),
      paths: paths,
      more: more,
      actions: [
        (key: const Key('ai.revert.cancel'), label: s.actionCancel, value: null, red: false, outlined: false),
        (
          key: const Key('ai.revert.confirm'),
          label: turn == null ? s.aiRevertSession : s.aiRevertTurn,
          value: 'yes',
          red: true,
          outlined: false,
        ),
      ],
    ),
  );
  return chosen == 'yes';
}

/// V2-2b B19, B20: the computer's question when files changed after the turn (the desktop's B14): Cancel, "Chỉ tệp
/// chưa đổi sau đó" (when some did not change) and "Hoàn tác hết". The keep word to send, or null for Cancel.
Future<String?> showAiRevertTouched(BuildContext context, AiRevertConfirm question) {
  final s = S.of(context);
  return showDialog<String>(
    context: context,
    builder: (context) => _SettledQuestion(
      key: const Key('ai.revert.touched'),
      title: s.aiRevertTouched(question.touchedCount),
      paths: question.touched,
      more: question.more,
      actions: [
        (key: const Key('ai.revert.cancel'), label: s.actionCancel, value: null, red: false, outlined: false),
        if (question.someClean)
          (key: const Key('ai.revert.clean'), label: s.aiRevertOnlyClean, value: 'clean', red: false, outlined: true),
        (key: const Key('ai.revert.all'), label: s.aiRevertAll, value: 'all', red: true, outlined: false),
      ],
    ),
  );
}

typedef _Action = ({Key key, String label, String? value, bool red, bool outlined});

/// A question about files whose buttons ignore taps for [_kSettle] after it appears.
class _SettledQuestion extends StatefulWidget {
  const _SettledQuestion({
    super.key,
    required this.title,
    required this.paths,
    required this.more,
    required this.actions,
  });

  final String title;
  final List<String> paths;
  final int more;
  final List<_Action> actions;

  @override
  State<_SettledQuestion> createState() => _SettledQuestionState();
}

class _SettledQuestionState extends State<_SettledQuestion> {
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _settle = Timer(_kSettle, () {
      if (mounted) setState(() => _settle = null);
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final settled = _settle == null;
    final mono = context.typo.paragraph13.copyWith(fontFamily: FontFamily.jetBrainsMono, color: colors.primaryText);
    final rest = widget.more + (widget.paths.length > _kListed ? widget.paths.length - _kListed : 0);
    return AlertDialog(
      title: Text(widget.title, style: context.typo.subHeader.bold),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final path in widget.paths.take(_kListed)) Text(path, style: mono),
            if (rest > 0) ...[
              4.sizedHeight,
              Text(s.aiChangesMore(rest), style: context.typo.paragraph13.copyWith(color: colors.secondaryText)),
            ],
          ],
        ),
      ),
      actions: [
        for (final a in widget.actions)
          if (a.outlined)
            OutlinedButton(
              key: a.key,
              onPressed: settled ? () => Navigator.of(context).pop(a.value) : null,
              child: Text(a.label),
            )
          else if (a.red)
            FilledButton(
              key: a.key,
              style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.white),
              onPressed: settled ? () => Navigator.of(context).pop(a.value) : null,
              child: Text(a.label),
            )
          else
            TextButton(
              key: a.key,
              onPressed: settled ? () => Navigator.of(context).pop(a.value) : null,
              child: Text(a.label),
            ),
      ],
    );
  }
}
