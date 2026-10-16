import 'dart:async';

import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_text.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart' show AiDiffLineRow;
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2b B20: one changed file's diff, full screen — its changed region as the computer read it now (before [turn],
/// or before the session when [turn] is null, against the disk), up to 20 KiB a side: removed and added lines in
/// monospace, one widget per visible line. A binary file, a file there neither before nor now, or one too large say
/// so instead.
@RoutePage()
class AiFileDiffPage extends StatefulWidget {
  const AiFileDiffPage({super.key, required this.controller, required this.path, this.turn});

  /// The session page's controller (its page is under this one).
  final AiSessionController controller;

  /// Relative to the session folder, as the Changes sheet listed it.
  final String path;
  final int? turn;

  @override
  State<AiFileDiffPage> createState() => _AiFileDiffPageState();
}

class _AiFileDiffPageState extends State<AiFileDiffPage> {
  var _loaded = false;
  String? _note;
  MirrorDiff? _diff;
  List<DiffLine> _lines = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final result = await widget.controller.loadDiff(widget.path, turn: widget.turn);
    if (!mounted) return;
    final s = S.of(context);
    final body = result.diff;
    final diff = body == null ? null : aiFileDiffOf(body);
    setState(() {
      _loaded = true;
      _diff = diff;
      _lines = diff == null ? const [] : diffLines(diff.oldText, diff.newText);
      _note = switch (result.code) {
        final code? => AiWords.failure(s, code) ?? s.aiRefused,
        null when diff != null => null,
        null when jBool(body ?? const {}, 'binary') => s.aiDiffBinary,
        null => s.aiDiffMissing,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final turn = widget.turn;
    final diff = _diff;
    final note = _note;
    return Scaffold(
      key: const Key('ai.fileDiff'),
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('ai.fileDiff.back'),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    icon: Icon(Icons.arrow_back_ios_new, color: colors.primary),
                    onPressed: () => context.router.maybePop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AiWords.fileName(widget.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typo.subHeader.bold.copyWith(color: colors.primaryText),
                        ),
                        2.sizedHeight,
                        Text(
                          [
                            turn == null ? s.aiDiffVsSession : s.aiDiffVsTurn(turn),
                            if (diff != null) '+${diff.plus} −${diff.minus}',
                            if (diff != null && diff.oldText == null) s.aiCreated,
                          ].join(' · '),
                          style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : note != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        note,
                        key: const Key('ai.fileDiff.note'),
                        textAlign: TextAlign.center,
                        style: context.typo.paragraph.copyWith(color: colors.secondaryText),
                      ),
                    )
                  : _Lines(lines: _lines, cut: diff?.cut ?? false),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lines of a diff region, built only as they scroll into view, in the conversation's diff rows ([AiDiffLineRow],
/// as "Xem đủ" shows them): a line too long for the screen wraps, and one longer than [kShownLineChars] is cut.
class _Lines extends StatelessWidget {
  const _Lines({required this.lines, required this.cut});

  final List<DiffLine> lines;
  final bool cut;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView.builder(
      key: const Key('ai.fileDiff.lines'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: lines.length + (cut ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == lines.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              S.of(context).aiFromComputerOnly,
              style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
            ),
          );
        }
        return AiDiffLineRow(line: lines[i]);
      },
    );
  }
}
