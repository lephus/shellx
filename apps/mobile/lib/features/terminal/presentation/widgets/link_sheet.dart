import 'package:flutter/services.dart';
import 'package:shellx_core/shellx_core.dart' show webUriOf;
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// A tap on a web address in the terminal (A10 D12): never opened straight away — a stray tap in a
/// full-screen program is common — but offered: Open or Copy link. Only http and https get here.
Future<void> showLinkSheet(BuildContext context, String url) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  backgroundColor: context.colors.surface,
  builder: (context) => _LinkSheet(url: url),
);

class _LinkSheet extends StatelessWidget {
  const _LinkSheet({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.linkSheetTitle, style: context.typo.subHeader.bold),
            const SizedBox(height: 8),
            SelectableText(
              url,
              key: const ValueKey('link-sheet-url'),
              maxLines: 6,
              style: TextStyle(fontFamily: FontFamily.jetBrainsMono, fontSize: 13, color: context.colors.primaryText),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('link-sheet-copy'),
                    onPressed: () async {
                      final done = strings.copied;
                      Navigator.of(context).pop();
                      try {
                        await Clipboard.setData(ClipboardData(text: url));
                        getIt<PopupHandler>().showSuccess(title: done);
                      } catch (_) {
                        // Nothing to say about a clipboard that cannot be written; never log the link.
                      }
                    },
                    child: Text(strings.linkSheetCopy),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('link-sheet-open'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      final uri = webUriOf(url);
                      if (uri != null) getIt<ExternalLinks>().openOrToast(uri);
                    },
                    child: Text(strings.linkSheetOpen),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
