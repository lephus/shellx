import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/desktop_services.dart' show desktopServicesProvider;
import '../../terminal/local_sessions_provider.dart' show appL10nProvider;
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_dock.dart';
import '../../tools/tool_embed.dart';
import '../../tools/tool_entry.dart';
import '../../tools/tool_registry.dart';
import '../window_router.dart';
import 'tool_dialogs.dart';

/// D3, D4: the workspace whose dock the window shows — the one shown
/// without a tab ([ToolDocks.loose]), else the selected tab's, else the
/// current one.
String dockWorkspaceOf(
  ToolDocks docks,
  TerminalTabsState tabs,
  SidebarState sidebar,
) {
  final selected = tabs.selectedId;
  return docks.loose ??
      (selected == null ? null : sidebar.workspaceOf(selected)) ??
      sidebar.currentId;
}

/// What ⌘⇧B did (D10, D20).
enum ToolToggle { opened, closed, asked, nothing }

/// The window's tool commands (D4, D10, D15, D20–D23) for the sidebar, the
/// palette, the AI header and Settings. Opening, toggling and adding run
/// through the window's intents, which also move the keyboard.
final class ToolActions {
  const ToolActions(this.ref);
  final WidgetRef ref;

  ToolRegistry get _registry => ref.read(toolRegistryProvider.notifier);
  ToolDockController get _dock => ref.read(toolDockProvider.notifier);
  bool get _embedded => ref.read(toolsEmbeddedProvider);

  String currentWorkspace() => dockWorkspaceOf(
    ref.read(toolDockProvider),
    ref.read(terminalTabsProvider),
    ref.read(sidebarWorkspacesProvider),
  );

  /// D4, D20: [toolId]'s workspace shows (its last tab, else its first,
  /// else none — D4's empty content area) and its dock opens on the tool.
  /// Not embedded: the system browser. True when the dock shows it.
  Future<bool> open(String toolId) async {
    final tool = _registry.byId(toolId);
    if (tool == null) return false;
    if (!_embedded) {
      await openInBrowser(tool);
      return false;
    }
    _showWorkspace(tool.ws);
    _dock.open(tool.ws, tool.id);
    return true;
  }

  void _showWorkspace(String ws) {
    final tabs = ref.read(terminalTabsProvider);
    final sidebar = ref.read(sidebarWorkspacesProvider);
    final selected = tabs.selectedId;
    if (selected != null && sidebar.workspaceOf(selected) == ws) {
      if (ref.read(toolDockProvider).loose != null) _dock.clearLoose();
      return;
    }
    final tab = _dock.lastTabOf(ws) ?? sidebar.tabsOf(ws).firstOrNull;
    if (tab != null) {
      ref.read(sidebarWorkspacesProvider.notifier).reveal(tab);
      ref.read(terminalTabsProvider.notifier).select(tab);
      return;
    }
    _dock.showLoose(ws);
  }

  /// D10, D20: ⌘⇧B on the shown workspace.
  Future<ToolToggle> toggle(BuildContext context) async {
    final ws = currentWorkspace();
    final tools = _registry.inWorkspace(ws);
    if (!_embedded) {
      if (tools.isNotEmpty) return ToolToggle.nothing;
      final added = await add(context, ws);
      return added == null ? ToolToggle.nothing : ToolToggle.asked;
    }
    final dock = ref.read(toolDockProvider).of(ws);
    if (dock.open) {
      _dock.close(ws);
      return ToolToggle.closed;
    }
    if (_dock.reopen(ws)) return ToolToggle.opened;
    if (tools.isEmpty) {
      final added = await add(context, ws);
      if (added == null) return ToolToggle.nothing;
      return await open(added.id) ? ToolToggle.opened : ToolToggle.asked;
    }
    final last = _dock.lastViewedOf(ws);
    final tool = tools.where((t) => t.id == last).firstOrNull ?? tools.first;
    return await open(tool.id) ? ToolToggle.opened : ToolToggle.nothing;
  }

  /// §4.2: the dialog for a new tool of [ws]; the tool, or null.
  Future<ToolEntry?> add(BuildContext context, String ws) async {
    final draft = await showToolDialog(context, ws: ws);
    if (draft == null) return null;
    return _registry.add(
      ws: ws,
      name: draft.name,
      url: draft.url,
      phone: draft.phone,
    );
  }

  /// D23: name, URL and phone flag in the same dialog.
  Future<void> edit(BuildContext context, ToolEntry tool) async {
    final draft = await showToolDialog(context, ws: tool.ws, existing: tool);
    if (draft == null) return;
    _registry.update(
      tool.copyWith(name: draft.name, url: draft.url, phone: draft.phone),
    );
  }

  /// D23: asks first; the chip and the page go with the tool.
  Future<void> delete(ToolEntry tool) async {
    final l10n = ref.read(appL10nProvider);
    final yes = await ref
        .read(windowRouterProvider.notifier)
        .confirm(
          ConfirmRequest(
            title: toolDeleteQuestion(l10n, tool),
            body: '',
            confirmLabel: l10n.toolDeleteAction,
          ),
        );
    if (yes) _registry.remove(tool.id);
  }

  /// D17 ↗, D20, D21: the tool's URL (or [url], a page or a download it
  /// reached) in the system browser.
  Future<void> openInBrowser(ToolEntry tool, {Uri? url}) =>
      _outside(url ?? tool.uri);

  /// D9: a page's new window goes to the browser, `mailto:`/`tel:` to the
  /// system.
  Future<void> openOutside(Uri url) => _outside(url);

  Future<void> _outside(Uri url) async {
    final opener = ref.read(desktopServicesProvider).urlOpener;
    final scheme = url.scheme.toLowerCase();
    try {
      if (scheme == 'mailto' || scheme == 'tel') {
        await opener.openMailOrPhone(url);
      } else {
        await opener.openWebLink(url);
      }
    } on Object catch (error) {
      debugPrint('tool: not opened outside (${error.runtimeType})');
      ref
          .read(terminalTabsProvider.notifier)
          .showNotice(const LinkOpenFailedNotice());
    }
  }

  /// D15: on or off; only a tool a phone may open turns on.
  void togglePhone(ToolEntry tool) {
    if (!tool.phoneAllowed) return;
    _registry.update(tool.copyWith(phone: !tool.phone));
  }

  /// D17 ⋯ "Copy URL": the tool's own URL.
  Future<void> copyUrl(ToolEntry tool) =>
      Clipboard.setData(ClipboardData(text: tool.url));
}
