import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_theme.dart';
import 'ai_tool_card.dart' show aiCapText;

/// D17: splits [text] into blocks at blank lines outside fenced code, so a
/// streaming message re-renders only its last block.
List<String> splitMarkdownBlocks(String text) {
  final blocks = <String>[];
  final current = StringBuffer();
  String? fence;
  for (final line in text.split('\n')) {
    final trimmed = line.trimLeft();
    if (fence == null &&
        (trimmed.startsWith('```') || trimmed.startsWith('~~~'))) {
      fence = trimmed.substring(0, 3);
    } else if (fence != null && trimmed.startsWith(fence)) {
      fence = null;
    }
    if (fence == null && line.trim().isEmpty) {
      if (current.isNotEmpty) {
        blocks.add(current.toString());
        current.clear();
      }
      continue;
    }
    if (current.isNotEmpty) current.write('\n');
    current.write(line);
  }
  if (current.isNotEmpty) blocks.add(current.toString());
  return blocks;
}

/// The agent's markdown (D17). Smoothness: one widget per block, and a
/// block whose text did not change is the same widget, so streaming
/// rebuilds the last block only; a block over [AiSizes.markdownBlockMax]
/// characters is plain text. Privacy (B15): images never load (their alt
/// text shows), links open only on a click, and only http/https.
class AiMarkdown extends StatefulWidget {
  const AiMarkdown({super.key, required this.text});
  final String text;

  /// Times a block was (re)built (tests: the streaming bound).
  @visibleForTesting
  static int debugBlockBuilds = 0;

  @override
  State<AiMarkdown> createState() => _AiMarkdownState();
}

class _AiMarkdownState extends State<AiMarkdown> {
  var _blocks = <(String, Widget)>[];

  @override
  Widget build(BuildContext context) {
    final texts = splitMarkdownBlocks(widget.text);
    _blocks = [
      for (final (i, t) in texts.indexed)
        i < _blocks.length && _blocks[i].$1 == t
            ? _blocks[i]
            : (t, _Block(key: ValueKey(i), text: t)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final (_, w) in _blocks) w],
    );
  }
}

class _Block extends ConsumerWidget {
  const _Block({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AiMarkdown.debugBlockBuilds++;
    const body = TextStyle(
      fontSize: 13,
      height: 20 / 13,
      color: ShellxDesktopColors.textPrimary,
    );
    // Past that length the block is plain text, capped like an output: a
    // code block of a megabyte shows its start and end.
    final child = text.length > AiSizes.markdownBlockMax
        ? Text(
            aiCapText(
              text,
              (hidden) =>
                  '… ${AppLocalizations.of(context).aiOutputCut(hidden)} …',
            ),
            style: kAiMono,
          )
        : MarkdownBody(
            data: text,
            // B15: never fetch what an agent's text points at.
            imageBuilder: (uri, title, alt) => Text(
              '[${alt ?? title ?? ''}]',
              style: body.copyWith(color: ShellxDesktopColors.textSecondary),
            ),
            onTapLink: (text, href, title) => _open(ref, href),
            styleSheet: MarkdownStyleSheet(
              p: body,
              a: body.copyWith(
                color: ShellxDesktopColors.accent,
                decoration: TextDecoration.underline,
              ),
              code: kAiMono.copyWith(
                backgroundColor: ShellxDesktopColors.surfaceInset,
              ),
              codeblockDecoration: BoxDecoration(
                color: ShellxDesktopColors.surfaceInset,
                borderRadius: BorderRadius.circular(ShellxRadius.r6),
                border: Border.all(color: ShellxDesktopColors.border),
              ),
              codeblockPadding: const EdgeInsets.all(ShellxSpace.s8),
              h1: ShellxText.emptyTitle.copyWith(
                color: ShellxDesktopColors.textTitle,
              ),
              h2: ShellxText.bodyStrong.copyWith(
                fontSize: 14,
                color: ShellxDesktopColors.textTitle,
              ),
              h3: ShellxText.bodyStrong.copyWith(
                color: ShellxDesktopColors.textTitle,
              ),
              listBullet: body,
              blockquote: body.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
              blockquoteDecoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: ShellxDesktopColors.line, width: 3),
                ),
              ),
              tableBody: body,
              tableHead: body.copyWith(fontWeight: FontWeight.w600),
              horizontalRuleDecoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: ShellxDesktopColors.line),
                ),
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: ShellxSpace.s8),
      child: child,
    );
  }

  static void _open(WidgetRef ref, String? href) {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    unawaited(
      ref.read(desktopServicesProvider).urlOpener.openWebLink(uri).catchError((
        Object e,
      ) {
        debugPrint('ShellX: link not opened: ${e.runtimeType}');
      }),
    );
  }
}
