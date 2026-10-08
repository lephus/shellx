import 'package:shellx_agent/shellx_agent.dart';

import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';

/// A7 D12: what a command acts on. `@self`/`@tab` are resolved by the CLI
/// itself; `@focused` reaches the window as is.
sealed class CliTarget {
  const CliTarget();
}

final class PaneRef extends CliTarget {
  const PaneRef(this.id);
  final int id;
}

final class TabRef extends CliTarget {
  const TabRef(this.id);
  final int id;
}

/// The focused pane of the selected tab (or that tab).
final class FocusedRef extends CliTarget {
  const FocusedRef();
}

const _focused = '@focused';

CliFailure _bad(String message) => CliFailure(MuxError.badRequest, message);

/// Canonical only (no leading zeros, no `-0`): what `shellx ls` prints and
/// the Rust CLI sends.
final _paneForm = RegExp(r'^p(0|-?[1-9]\d{0,14})$');
final _tabForm = RegExp(r'^t([1-9]\d{0,14})$');

/// D12 on the wire: exactly one of [pane] and [tab], each an id, its
/// written form (`p<id>`, `p-<n>`, `t<id>`) or `"@focused"`. A `pane`
/// given as `t<id>` is that tab (final ruling M4: [resolvePane] gives its
/// focused pane). [forward] maps a pane id to the session that replaced it
/// (A8 D22: `TerminalTabs.resolveReplaced`), so a script that kept `p41`
/// across a reconnect still reaches the pane; tab ids never change.
CliTarget parseTarget(
  Object? pane,
  Object? tab, {
  int Function(int id)? forward,
}) {
  if ((pane == null) == (tab == null)) {
    throw _bad('give exactly one pane or tab');
  }
  final value = pane ?? tab;
  if (value == _focused) return const FocusedRef();
  if (pane is String) {
    if (_tabForm.firstMatch(pane) case final m?) {
      return TabRef(int.parse(m[1]!));
    }
  }
  final id = switch (value) {
    final int id => id,
    final String s => switch ((pane != null ? _paneForm : _tabForm).firstMatch(
      s,
    )) {
      final m? => int.parse(m[1]!),
      null => throw _bad('a target is an id or @focused'),
    },
    _ => throw _bad('a target is an id or @focused'),
  };
  return pane != null ? PaneRef(forward?.call(id) ?? id) : TabRef(id);
}

CliFailure _noPane(int id) => CliFailure(MuxError.notFound, 'no pane p$id');
CliFailure _noTab(int id) => CliFailure(MuxError.notFound, 'no tab t$id');
const _noSelection = CliFailure(MuxError.notFound, 'no tab is selected');

TerminalTab? _tabById(TerminalTabsState s, int id) =>
    s.tabs.where((t) => t.id == id).firstOrNull;

/// A terminal pane id; a tab gives its focused pane. Throws `not_found`.
int resolvePane(TerminalTabsState s, CliTarget target) => switch (target) {
  FocusedRef() => (s.selected ?? (throw _noSelection)).focusedPaneId,
  PaneRef(:final id) => s.tabOfSession(id) != null ? id : throw _noPane(id),
  TabRef(:final id) => (_tabById(s, id) ?? (throw _noTab(id))).focusedPaneId,
};

/// A tab id; a pane gives the tab holding it. Throws `not_found`.
int resolveTab(TerminalTabsState s, CliTarget target) => switch (target) {
  FocusedRef() => (s.selected ?? (throw _noSelection)).id,
  TabRef(:final id) => (_tabById(s, id) ?? (throw _noTab(id))).id,
  PaneRef(:final id) => (s.tabOfSession(id) ?? (throw _noPane(id))).id,
};

/// D12: a workspace by id (`w:<id>` or bare) or by its shown name, ignoring
/// case. Throws `ambiguous` when several share the name, else `not_found`.
String resolveWorkspace(
  SidebarState s,
  String key,
  String Function(String id) displayName,
) {
  final k = key.startsWith('w:') ? key.substring(2) : key;
  if (s.workspace(k) != null) return k;
  final lower = k.toLowerCase();
  final hits = [
    for (final w in s.workspaces)
      if (displayName(w.id).toLowerCase() == lower) w.id,
  ];
  if (hits.length == 1) return hits.single;
  if (hits.isEmpty) {
    throw CliFailure(MuxError.notFound, 'no workspace "$key"');
  }
  throw CliFailure(
    CliError.ambiguous,
    '${hits.length} workspaces are named "$key"; use w:<id> (shellx ls)',
  );
}

/// A11 D26 (c): the workspace the caller lives in, for a tab opened without
/// `--workspace`. The pane (`fromPane`, the CLI's `$SHELLX_PANE_ID`) is
/// looked up *now*, so a pane that moved to another tab, or a tab dragged to
/// another workspace, counts where it is; a pane that is gone falls back to
/// `fromTab` (`$SHELLX_TAB_ID`); null when neither is alive, and the caller
/// then uses the current workspace as before. Anything that is not an
/// integer is ignored: a stale or odd environment never fails a command.
String? resolveCallerWorkspace(
  TerminalTabsState tabs,
  SidebarState side, {
  Object? fromPane,
  Object? fromTab,
}) {
  if (fromPane is int) {
    final tab = tabs.tabOfSession(fromPane);
    final ws = tab == null ? null : side.workspaceOf(tab.id);
    if (ws != null) return ws;
  }
  if (fromTab is int && _tabById(tabs, fromTab) != null) {
    return side.workspaceOf(fromTab);
  }
  return null;
}
