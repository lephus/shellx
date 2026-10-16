import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../terminal/terminal_overlays.dart' show ShellxPrimaryButton;
import '../theme/shellx_desktop_theme.dart';

/// A11 D23: the small card shown once after an update: up to five bullet
/// lines bundled with the app, "Got it", and "See all changes". Esc is
/// "Got it".
class WhatsNewCard extends StatefulWidget {
  const WhatsNewCard({
    super.key,
    required this.version,
    required this.notes,
    required this.onDone,
    required this.onMore,
  });
  final String version;

  /// Null or empty: the release has no notes (opened by hand).
  final List<String>? notes;
  final VoidCallback onDone;
  final VoidCallback onMore;

  @override
  State<WhatsNewCard> createState() => _WhatsNewCardState();
}

class _WhatsNewCardState extends State<WhatsNewCard> {
  final _done = FocusNode(debugLabel: 'whatsnew done');

  @override
  void initState() {
    super.initState();
    // "Got it" has the keyboard: Enter dismisses.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _done.requestFocus();
    });
  }

  @override
  void dispose() {
    _done.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onDone = widget.onDone, onMore = widget.onMore;
    final version = widget.version, notes = widget.notes;
    final l10n = AppLocalizations.of(context);
    final title = l10n.whatsNewTitle(version);
    final size = MediaQuery.sizeOf(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onDone},
        child: FocusScope(
          autofocus: true,
          child: Container(
            key: const Key('whatsnew.card'),
            width: (size.width - 48).clamp(280.0, 420.0),
            padding: const EdgeInsets.all(ShellxSpace.s16),
            decoration: BoxDecoration(
              color: ShellxDesktopColors.surface,
              borderRadius: BorderRadius.circular(ShellxRadius.r8),
              border: Border.all(color: ShellxDesktopColors.border),
              boxShadow: ShellxShadows.e1,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: ShellxText.emptyTitle.copyWith(
                        color: ShellxDesktopColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: ShellxSpace.s8),
                  for (final line in notes ?? const <String>[])
                    Padding(
                      padding: const EdgeInsets.only(bottom: ShellxSpace.s4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ExcludeSemantics(child: Text('•  ')),
                          Expanded(
                            child: Text(
                              line,
                              style: ShellxText.body.copyWith(
                                color: ShellxDesktopColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: ShellxSpace.s12),
                  Row(
                    children: [
                      TextButton(
                        key: const Key('whatsnew.more'),
                        onPressed: onMore,
                        child: Text(l10n.whatsNewMore),
                      ),
                      const Spacer(),
                      ShellxPrimaryButton(
                        key: const Key('whatsnew.done'),
                        label: l10n.whatsNewDone,
                        onPressed: onDone,
                        focusNode: _done,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
