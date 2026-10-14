import 'dart:async';

import 'package:flutter/widgets.dart' show Key;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../remote/remote_port_forwards.dart';
import '../../remote/ssh_reconnector.dart';
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/terminal_tabs.dart';
import 'remote_marks.dart';
import 'shellx_menu.dart';

/// The sidebar's SSH additions (UI-A8 §2.3): menu items and port tooltips,
/// kept out of `session_sidebar.dart`.
enum RemoteMenuAction { reconnect, newRemoteTab, newLocalTab, reconnectAll }

/// A row menu's first item: only for a tab with a lost pane (A3 §4.2).
List<ShellxMenuEntry<Object>> remoteRowEntries(
  AppLocalizations l10n,
  TerminalTab tab,
) => [
  if (tab.panes.values.any((p) => p.canReconnect))
    ShellxMenuEntry<Object>(
      key: const Key('menu.row.reconnect'),
      value: RemoteMenuAction.reconnect,
      label: l10n.rowReconnect,
    ),
];

/// A server workspace's header menu, first group (A2 §5.2).
List<ShellxMenuEntry<Object>> remoteHeaderEntries(
  AppLocalizations l10n,
  Workspace workspace, {
  required bool canReconnect,
}) {
  final host = workspace.ssh;
  if (host == null) return const [];
  return [
    ShellxMenuEntry<Object>(
      key: const Key('menu.ws.newRemoteTab'),
      value: RemoteMenuAction.newRemoteTab,
      label: l10n.workspaceNewRemoteTab(cleanServerText(host)),
    ),
    ShellxMenuEntry<Object>(
      key: const Key('menu.ws.newLocalTab'),
      value: RemoteMenuAction.newLocalTab,
      label: l10n.workspaceNewLocalTab,
    ),
    ShellxMenuEntry<Object>(
      key: const Key('menu.ws.reconnectAll'),
      value: RemoteMenuAction.reconnectAll,
      label: l10n.workspaceReconnectAll,
      enabled: canReconnect,
    ),
  ];
}

/// Whether a pane of [workspace]'s tabs can be reconnected.
bool workspaceCanReconnect(WidgetRef ref, String workspaceId) {
  final members = ref.read(sidebarWorkspacesProvider).tabsOf(workspaceId);
  return ref
      .read(terminalTabsProvider)
      .tabs
      .any(
        (t) =>
            members.contains(t.id) && t.panes.values.any((p) => p.canReconnect),
      );
}

/// Runs a [RemoteMenuAction] chosen from the row menu ([tab]) or a header
/// menu ([workspaceId]).
Future<void> runRemoteMenuAction(
  WidgetRef ref,
  RemoteMenuAction action, {
  TerminalTab? tab,
  String? workspaceId,
}) async {
  final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
  switch (action) {
    case RemoteMenuAction.reconnect:
      if (tab == null) return;
      final reconnector = ref.read(sshReconnectorProvider.notifier);
      await Future.wait([
        for (final p in tab.panes.values.toList())
          if (p.canReconnect) reconnector.reconnectNow(p.id),
      ]);
    case RemoteMenuAction.newRemoteTab:
      if (workspaceId != null) await workspaces.openTabIn(workspaceId);
    case RemoteMenuAction.newLocalTab:
      if (workspaceId != null) await workspaces.openLocalTabIn(workspaceId);
    case RemoteMenuAction.reconnectAll:
      if (workspaceId != null) {
        await ref
            .read(sshReconnectorProvider.notifier)
            .reconnectAll(workspaceId);
      }
  }
}

/// UI-A8 §2.4: a server's port says it is forwarded over SSH, and where to
/// once it is.
String remotePortTooltipFor(
  WidgetRef ref,
  AppLocalizations l10n,
  TerminalTab tab,
  int port,
) {
  final key = tab.focused?.remote?.hostKey;
  if (key == null) return l10n.portOpenTooltip(port);
  final host = cleanServerText(key);
  final local = ref
      .read(remotePortForwardsProvider.notifier)
      .forwarded(key, port);
  return local == null
      ? l10n.remotePortTooltip(port, host)
      : l10n.remotePortForwarded(local, host, port);
}
