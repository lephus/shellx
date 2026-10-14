import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/config_controller.dart' show shellxConfigProvider;
import '../config/shellx_config.dart' show NewTabKind;
import '../terminal/local_sessions_provider.dart'
    show appL10nProvider, homeDirectoryProvider;
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'ai_agents.dart';
import 'ai_paths.dart' show aiFolderIsBroad;

/// V2-1 D5: how AI tabs open — "New AI session", and "a new tab" when
/// `new-tab-kind = ai`.
final aiOpenerProvider = Provider<AiOpener>(AiOpener.new);

final class AiOpener {
  AiOpener(this._ref);
  final Ref _ref;

  /// "New AI session" (⌘⇧E, the sidebar's button, the `+` menu, the
  /// palette): an AI tab, selected, in workspace [workspaceId] (by default
  /// the current one), with the default agent (D23). Its folder is the
  /// workspace's project root, else the folder of the tab in front (see
  /// [_frontFolder]), else none: the pane asks for one (D5). Nothing starts
  /// until the pane shows (B11). Returns the tab's id; null when no agent is
  /// offered.
  int? newSession({String? workspaceId}) {
    final side = _ref.read(sidebarWorkspacesProvider);
    final id = workspaceId ?? side.currentId;
    final agent = _ref.read(aiDefaultAgentProvider);
    if (agent == null) return null;
    final front = _frontFolder(side, id);
    _ref.read(sidebarWorkspacesProvider.notifier).setCollapsed(id, false);
    return _ref
        .read(terminalTabsProvider.notifier)
        .openAiTab(
          agentId: agent.id,
          agentName: agent.name,
          title: _ref.read(appL10nProvider).aiNewSession,
          cwd: side.workspace(id)?.root ?? front,
          workspace: id,
        );
  }

  /// The folder of the tab in front, for a new session in workspace [id]
  /// (D5): never a server's, and only when that tab is one of [id]'s — the
  /// tab in front of another workspace is another project. A folder too
  /// broad to be a project (the home folder, a folder above it, a disk root:
  /// final review I-1) counts as none, so the pane asks for one instead of
  /// crawling all of it. A folder the user chooses on the card, or sets as a
  /// workspace's root, is theirs and is kept.
  String? _frontFolder(SidebarState side, String id) {
    final selected = _ref.read(terminalTabsProvider).selected;
    if (selected == null) return null;
    final workspace = side.workspaceOf(selected.id);
    if (workspace != null && workspace != id) return null;
    final folder = selected.isAi
        ? selected.ai?.cwd
        : (selected.focused?.remote == null ? selected.focused?.cwd : null);
    if (folder == null) return null;
    final home = _ref.read(homeDirectoryProvider);
    return aiFolderIsBroad(folder, home: home) ? null : folder;
  }

  /// D5: "a new tab" in workspace [workspaceId] (⌘T, the `+` buttons, the
  /// empty window): an AI session when `new-tab-kind = ai` and the
  /// workspace is on this computer (B8: a server's workspace keeps opening
  /// its server), else a terminal tab.
  Future<void> newTabIn(String workspaceId) async {
    if (_wantsAi(workspaceId) && newSession(workspaceId: workspaceId) != null) {
      return;
    }
    await _ref.read(sidebarWorkspacesProvider.notifier).openTabIn(workspaceId);
  }

  /// D5, D11: the tab that start-up and activation open when there is none,
  /// under the same rule. False: the caller opens a terminal tab.
  bool firstTab() {
    if (!_aiKind) return false;
    final id = _ref.read(sidebarWorkspacesProvider).currentId;
    return _wantsAi(id) && newSession(workspaceId: id) != null;
  }

  bool get _aiKind =>
      _ref.read(shellxConfigProvider).config.newTabKind == NewTabKind.ai;

  bool _wantsAi(String workspaceId) {
    if (!_aiKind) return false;
    final w = _ref.read(sidebarWorkspacesProvider).workspace(workspaceId);
    return w != null && w.ssh == null;
  }
}
