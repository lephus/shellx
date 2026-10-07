import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/domain/buffer_text.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:xterm/core.dart';

/// "View as text" (A10 D28): the terminal's recent text as a snapshot the user can select and copy
/// with the platform's own handles; one tap copies all of it. Static: a refresh button takes
/// another snapshot. Nothing here is logged.
Future<void> showViewAsTextSheet(BuildContext context, Terminal terminal) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: context.colors.surface,
  builder: (context) => ViewAsTextSheet(terminal: terminal),
);

class ViewAsTextSheet extends StatefulWidget {
  const ViewAsTextSheet({super.key, required this.terminal});

  final Terminal terminal;

  @override
  State<ViewAsTextSheet> createState() => _ViewAsTextSheetState();
}

class _ViewAsTextSheetState extends State<ViewAsTextSheet> {
  late ({String text, bool truncated}) _snapshot = terminalText(widget.terminal);
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _toEnd();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The newest output is at the end: that is where the user wants to start.
  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  void _refresh() {
    setState(() => _snapshot = terminalText(widget.terminal));
    _toEnd();
  }

  Future<void> _copyAll() async {
    final done = S.of(context).copied;
    try {
      await Clipboard.setData(ClipboardData(text: _snapshot.text));
    } catch (error) {
      if (kDebugMode) debugPrint('Clipboard error: ${error.runtimeType}');
      if (mounted) getIt<PopupHandler>().showError(title: ErrorText(S.of(context)).describe(error));
      return;
    }
    if (mounted) getIt<PopupHandler>().showSuccess(title: done);
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final empty = _snapshot.text.isEmpty;
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(strings.viewAsTextTitle, style: context.typo.subHeader.bold)),
                IconButton(
                  key: const ValueKey('view-as-text-refresh'),
                  tooltip: strings.viewAsTextRefresh,
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
                TextButton.icon(
                  key: const ValueKey('view-as-text-copy'),
                  onPressed: empty ? null : _copyAll,
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(strings.viewAsTextCopyAll),
                ),
              ],
            ),
            if (_snapshot.truncated)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  strings.viewAsTextTruncated(kViewAsTextMaxLines),
                  key: const ValueKey('view-as-text-truncated'),
                  style: context.typo.metadata11.copyWith(color: context.colors.secondaryText),
                ),
              ),
            Expanded(
              child: empty
                  ? Center(
                      child: Text(
                        strings.viewAsTextEmpty,
                        key: const ValueKey('view-as-text-empty'),
                        style: context.typo.paragraph.copyWith(color: context.colors.secondaryText),
                      ),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        // Long lines scroll sideways instead of wrapping: a command stays one line.
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SelectableText(
                            _snapshot.text,
                            key: const ValueKey('view-as-text-body'),
                            style: TextStyle(
                              fontFamily: FontFamily.jetBrainsMono,
                              fontSize: 13,
                              height: 1.35,
                              color: context.colors.primaryText,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
