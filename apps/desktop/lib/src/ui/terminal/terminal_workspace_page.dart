import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';
import 'close_tab.dart';
import 'session_sidebar.dart';
import 'terminal_pane.dart';

/// Spec §3.2: `Row(Sidebar 220 px, VerticalDivider, TerminalPane)`.
class TerminalWorkspacePage extends ConsumerStatefulWidget {
  const TerminalWorkspacePage({super.key});

  @override
  ConsumerState<TerminalWorkspacePage> createState() =>
      TerminalWorkspacePageState();
}

class TerminalWorkspacePageState extends ConsumerState<TerminalWorkspacePage> {
  final terminalFocus = FocusNode(debugLabel: 'terminal');
  final sidebarFocus = FocusNode(debugLabel: 'sidebar');

  /// The empty state's "Open new tab" (focused when the last tab closes).
  final emptyFocus = FocusNode(debugLabel: 'open new tab');
  final sidebarScroll = ScrollController();

  /// Map of shortcuts handed to every TerminalView (filled by Task 8).
  Map<ShortcutActivator, Intent>? terminalShortcuts;

  /// After the frame, so a TerminalView that just got [terminalFocus] (a
  /// new selection) is attached first.
  void focusTerminal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) terminalFocus.requestFocus();
  });

  Future<void> closeTab(TerminalTab tab) => closeTabWithConfirm(
    tabs: ref.read(terminalTabsProvider.notifier),
    router: ref.read(windowRouterProvider.notifier),
    l10n: AppLocalizations.of(context),
    tab: tab,
  );

  @override
  void initState() {
    super.initState();
    focusTerminal(); // UI §3.6: the terminal has the initial focus.
  }

  @override
  void dispose() {
    terminalFocus.dispose();
    sidebarFocus.dispose();
    emptyFocus.dispose();
    sidebarScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A new selection gets the keyboard (UI §3.6), except while the
    // sidebar has it: its arrow keys (Task 8) move the selection and must
    // keep the focus in the list.
    ref.listen(terminalTabsProvider.select((s) => s.selectedId), (_, id) {
      if (id != null && !sidebarFocus.hasFocus) focusTerminal();
    });
    // The last tab closed: the keyboard goes to "Open new tab" instead of
    // vanishing with the terminal (after the frame that builds the button).
    ref.listen(terminalTabsProvider.select((s) => s.tabs.isEmpty), (
      wasEmpty,
      empty,
    ) {
      if (empty && wasEmpty == false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) emptyFocus.requestFocus();
        });
      }
    });
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: ShellxSizes.sidebarWidth,
          child: SessionSidebar(
            focusNode: sidebarFocus,
            scrollController: sidebarScroll,
            onSelected: (id) {
              ref.read(terminalTabsProvider.notifier).select(id);
              focusTerminal();
            },
            onClose: closeTab,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: TerminalPane(
            terminalFocus: terminalFocus,
            emptyFocus: emptyFocus,
            shortcuts: terminalShortcuts,
          ),
        ),
      ],
    );
  }
}
