import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_dock.dart';
import '../../tools/tool_dock_state.dart';
import '../../tools/tool_embed.dart';
import 'tool_dock_view.dart';

/// D3: the content area — the panes, and the shown workspace's dock beside
/// them (or over them, zoomed). The panes keep their place in the tree and
/// their width while the dock is zoomed, so no terminal is resized by it.
/// D4: a workspace shown without a tab gets [loosePanel] over the panes.
class ToolArea extends ConsumerWidget {
  const ToolArea({
    super.key,
    required this.panes,
    required this.dockFocus,
    required this.covered,
    required this.onChord,
    required this.onLeave,
    required this.loosePanel,
  });

  final Widget panes;
  final FocusNode dockFocus;
  final bool covered;
  final void Function(String chord) onChord;
  final VoidCallback onLeave;
  final Widget Function(String ws) loosePanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docks = ref.watch(toolDockProvider);
    final tabs = ref.watch(
      terminalTabsProvider.select((s) => (s.selectedId, s.tabs.length)),
    );
    final sidebar = ref.watch(sidebarWorkspacesProvider);
    final embedded = ref.watch(toolsEmbeddedProvider);
    final ws = dockWorkspaceOf(docks, tabs.$1, sidebar);
    final dock = docks.of(ws);
    final loose = docks.loose;
    // The rule of toolPanesCoveredProvider (A4 "seen", A12 "watched", the
    // drop targets): the two never disagree.
    final hidden = toolPanesCovered(docks, shown: dock, embedded: embedded);
    return LayoutBuilder(
      builder: (context, c) {
        final layout = toolDockLayout(
          width: c.maxWidth,
          dock: dock,
          embedded: embedded,
        );
        return Stack(
          children: [
            Positioned(
              key: const ValueKey('tool.panesSlot'),
              left: 0,
              top: 0,
              bottom: 0,
              width: layout.paneWidth,
              child: ExcludeSemantics(
                excluding: hidden,
                child: ExcludeFocus(excluding: hidden, child: panes),
              ),
            ),
            if (loose != null)
              Positioned(
                key: const ValueKey('tool.looseSlot'),
                left: 0,
                top: 0,
                bottom: 0,
                width: layout.paneWidth,
                child: loosePanel(loose),
              ),
            if (layout.showsHandle)
              Positioned(
                key: const ValueKey('tool.handleSlot'),
                left: layout.paneWidth,
                top: 0,
                bottom: 0,
                width: kToolDockHandle,
                child: ToolDockHandle(
                  contentWidth: c.maxWidth,
                  dockWidth: layout.dockWidth,
                  fraction: dock.width,
                  onFraction: (f) =>
                      ref.read(toolDockProvider.notifier).setWidth(ws, f),
                ),
              ),
            if (layout.showsDock)
              Positioned(
                key: const ValueKey('tool.dockSlot'),
                left: layout.dockLeft,
                top: 0,
                bottom: 0,
                width: layout.dockWidth,
                child: ToolDockView(
                  key: ValueKey('tool.dock.$ws'),
                  workspaceId: ws,
                  focusNode: dockFocus,
                  covered: covered,
                  onChord: onChord,
                  onLeave: onLeave,
                ),
              ),
          ],
        );
      },
    );
  }
}
