import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_changes_panel.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// The AI pane's right panel (spec §4.1, §4.4), 268 px: "Changes", and
/// "Files" once [files] is given (Task 25). The tabs switch at once (no
/// animation); which one shows is the pane's ([AiPaneUi.panelTab]).
class AiSidePanel extends StatelessWidget {
  const AiSidePanel({super.key, this.files});

  /// The Files tab; null: Changes alone.
  final Widget? files;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ui = AiPaneScope.of(context).ui;
    final files = this.files;
    Widget tab(AiPanelTab which, String label, Key key) {
      final on = ui.panelTab == which;
      return TextButton(
        key: key,
        onPressed: () => ui.showTab(which),
        child: Text(
          label,
          style: ShellxText.bodyStrong.copyWith(
            color: on
                ? ShellxDesktopColors.textPrimary
                : ShellxDesktopColors.textSecondary,
          ),
        ),
      );
    }

    return SizedBox(
      key: const Key('ai.sidePanel'),
      width: AiSizes.panel,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: ShellxDesktopColors.bgSidebar,
          border: Border(left: BorderSide(color: ShellxDesktopColors.line)),
        ),
        child: ListenableBuilder(
          listenable: ui,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s4),
                child: Row(
                  children: [
                    tab(
                      AiPanelTab.changes,
                      l10n.aiPanelChanges,
                      const Key('ai.panel.changes'),
                    ),
                    if (files != null)
                      tab(
                        AiPanelTab.files,
                        l10n.aiPanelFiles,
                        const Key('ai.panel.files'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: files == null
                    ? const AiChangesPanel()
                    : IndexedStack(
                        index: ui.panelTab.index,
                        sizing: StackFit.expand,
                        children: [const AiChangesPanel(), files],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
