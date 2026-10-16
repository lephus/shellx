import 'dart:async';
import 'dart:convert' show LineSplitter;

import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_text.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart' show AiDiffLineRow;
import 'package:shellx_mobile/shared/shared.dart';

/// Loads an item in full, telling [onPart] of each slice (1-based); the failure code when it cannot
/// ([AiWords.failure]). An error [onPart] throws ends the loading.
typedef AiFullLoader = Future<({AiFullView? view, String? code})> Function(void Function(int part, int parts) onPart);

/// V2-2b B16: "Xem đủ" — one item in full on its own page over the session: "Đang tải 3/12" while its
/// slices come, then its lines in a monospace font, built only near the screen (a text; a call's output,
/// every diff in the conversation's diff rows, its input; a question's words) — or why the phone cannot
/// show it (too big: on the computer). Leaving the page ends the loading.
@RoutePage()
class AiItemPage extends StatefulWidget {
  const AiItemPage({super.key, required this.title, required this.load});

  final String title;
  final AiFullLoader load;

  @override
  State<AiItemPage> createState() => _AiItemPageState();
}

/// One row of the page.
sealed class _Row {
  const _Row();
}

final class _Line extends _Row {
  const _Line(this.text);
  final String text;
}

final class _Diff extends _Row {
  const _Diff(this.line);
  final DiffLine line;
}

/// A file's path above its diff.
final class _Title extends _Row {
  const _Title(this.text);
  final String text;
}

/// Words of the app, not of the item.
final class _Note extends _Row {
  const _Note(this.text);
  final String text;
}

final class _Gap extends _Row {
  const _Gap();
}

/// What [_AiItemPageState] throws from its progress once it is gone: the loading ends.
final class _Left implements Exception {
  const _Left();
}

class _AiItemPageState extends State<AiItemPage> {
  int _part = 0;
  int _parts = 0;
  List<_Row>? _rows;
  String? _code;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final got = await widget.load((part, parts) {
      if (!mounted) throw const _Left();
      setState(() {
        _part = part;
        _parts = parts;
      });
    });
    if (!mounted) return;
    final view = got.view;
    final s = S.of(context);
    setState(() {
      if (view == null) {
        // A lost channel is said as a reconnection: nothing was asked to change.
        final code = got.code ?? 'refused';
        _code = code == AiWords.outcomeUnknown ? 'offline' : code;
      } else {
        _rows = _rowsOf(s, view);
      }
    });
  }

  static List<_Row> _rowsOf(S s, AiFullView view) {
    List<_Row> lines(String text) => [for (final l in const LineSplitter().convert(text)) _Line(l)];
    return [
      if (view.text case final text?) ...lines(text),
      if (view.request case final request?) ...lines(request.message),
      if (view.output case final output?) ...lines(output),
      for (final d in view.diffs) ...[
        const _Gap(),
        _Title(d.path),
        for (final l in diffLines(d.oldText, d.newText)) _Diff(l),
      ],
      for (final path in view.bigDiffs) ...[const _Gap(), _Title(path), _Note(s.aiFromComputerOnly)],
      if (view.input case final input?) ...[const _Gap(), ...lines(input)],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final rows = _rows;
    final code = _code;
    final Widget body;
    if (rows != null) {
      body = ListView.builder(
        key: const Key('ai.item.lines'),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: rows.length,
        itemBuilder: (context, i) => _row(context, rows[i]),
      );
    } else if (code != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            AiWords.failure(s, code) ?? s.somethingWentWrong,
            key: const Key('ai.item.error'),
            textAlign: TextAlign.center,
            style: context.typo.paragraph.copyWith(color: colors.secondaryText),
          ),
        ),
      );
    } else {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_parts > 0) ...[
              12.sizedHeight,
              Text(
                s.aiLoadingParts(_part, _parts),
                key: const Key('ai.item.loading'),
                style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
              ),
            ],
          ],
        ),
      );
    }
    return Scaffold(
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
                    key: const Key('ai.item.back'),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    icon: Icon(Icons.arrow_back_ios_new, color: colors.primary),
                    onPressed: () => context.router.maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      key: const Key('ai.item.title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.subHeader.bold.copyWith(color: colors.primaryText),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _Row row) {
    final colors = context.colors;
    return switch (row) {
      _Line(:final text) => Text(
        clipLine(text),
        style: TextStyle(fontFamily: FontFamily.jetBrainsMono, fontSize: 12, height: 1.35, color: colors.primaryText),
      ),
      _Diff(:final line) => AiDiffLineRow(line: line),
      _Title(:final text) => Text(text, style: context.typo.metadata12.bold.copyWith(color: colors.secondaryText)),
      _Note(:final text) => Text(text, style: context.typo.paragraph13.copyWith(color: colors.secondaryText)),
      _Gap() => 10.sizedHeight,
    };
  }
}
