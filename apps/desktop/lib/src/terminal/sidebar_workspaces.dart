import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../l10n/app_localizations.dart';
import '../agent/agent_controller_base.dart';
import '../agent/desktop_services.dart';
import '../platform/settings_store.dart';
import '../remote/ssh_settings.dart';
import '../restore/restore_snapshot.dart';
import 'local_sessions_provider.dart';
import 'tab_meta.dart';
import 'terminal_font_size.dart';
import 'terminal_style.dart' show kTerminalFontSizeMax, kTerminalFontSizeMin;
import 'terminal_tabs.dart';

const String kDefaultWorkspaceId = 'default';
const int kWorkspaceNameMaxLength = 64;

/// A11 D19: how far a workspace's text size may sit from the global one,
/// in points.
const double kWorkspaceFontStepMin = -6;
const double kWorkspaceFontStepMax = 10;

/// At most [kWorkspaceNameMaxLength] user-perceived characters (a cut
/// never splits an accent from its letter), trimmed after the cut.
String _clip(String text) => clipName(text, kWorkspaceNameMaxLength);

/// A named group of tabs in the sidebar (spec C5).
@immutable
final class Workspace {
  const Workspace({
    required this.id,
    this.name,
    this.collapsed = false,
    this.ssh,
    this.fontStep = 0,
  });

  final String id;

  /// Null only for the Default workspace never renamed: it shows the
  /// localized "Mặc định"/"Default" (D11).
  final String? name;
  final bool collapsed;

  /// A8 D23: the server this workspace opens tabs on ([SshTarget.key]);
  /// null for a local workspace.
  final String? ssh;

  /// A11 D19: points added to the global text size for every tab here
  /// (JSON key `zoom`; −6…+10; 0 when missing or odd).
  final double fontStep;

  bool get isDefault => id == kDefaultWorkspaceId;

  String displayName(AppLocalizations l10n) =>
      name ?? l10n.workspaceDefaultName;

  Workspace copyWith({String? name, bool? collapsed, double? fontStep}) =>
      Workspace(
        id: id,
        name: name ?? this.name,
        collapsed: collapsed ?? this.collapsed,
        ssh: ssh,
        fontStep: fontStep ?? this.fontStep,
      );

  String encode() => jsonEncode({
    'id': id,
    if (name != null) 'name': name,
    'collapsed': collapsed,
    if (ssh != null) 'ssh': ssh,
    if (fontStep != 0) 'zoom': fontStep,
  });

  /// Null for anything that is not a well-formed entry (Review Focus 5).
  static Workspace? decode(String text) {
    final Object? value;
    try {
      value = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (value is! Map<String, Object?>) return null;
    final id = value['id'];
    final name = value['name'];
    final collapsed = value['collapsed'];
    final rawSsh = value['ssh'];
    final rawZoom = value['zoom'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (name != null && name is! String) return null;
    if (collapsed != null && collapsed is! bool) return null;
    final clean = (name as String?)?.trim() ?? '';
    if (clean.isEmpty && id != kDefaultWorkspaceId) return null;
    // A8 D23: only a canonical key; anything else leaves a local workspace.
    final ssh = rawSsh is String && SshTarget.parseKey(rawSsh) != null
        ? rawSsh
        : null;
    return Workspace(
      id: id,
      name: clean.isEmpty ? null : _clip(clean),
      collapsed: collapsed as bool? ?? false,
      ssh: id == kDefaultWorkspaceId ? null : ssh,
      // A11 D19: anything but a finite number is no zoom; a number is cut
      // to the allowed range.
      fontStep: rawZoom is num && rawZoom.isFinite
          ? rawZoom
                .toDouble()
                .clamp(kWorkspaceFontStepMin, kWorkspaceFontStepMax)
                .toDouble()
          : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Workspace &&
      other.id == id &&
      other.name == name &&
      other.collapsed == collapsed &&
      other.ssh == ssh &&
      other.fontStep == fontStep;

  @override
  int get hashCode => Object.hash(id, name, collapsed, ssh, fontStep);
}

/// The stored list, without broken or duplicate entries, and always with
/// a Default (first when it was missing).
List<Workspace> loadWorkspaces(List<String> stored) {
  final result = <Workspace>[];
  final ids = <String>{};
  for (final text in stored) {
    final workspace = Workspace.decode(text);
    if (workspace == null || !ids.add(workspace.id)) continue;
    result.add(workspace);
  }
  if (!ids.contains(kDefaultWorkspaceId)) {
    result.insert(0, const Workspace(id: kDefaultWorkspaceId));
  }
  return result;
}

/// The item whose inline name field is open (UI-A2 §4).
sealed class RenameTarget {
  const RenameTarget();
}

final class RenameTab extends RenameTarget {
  const RenameTab(this.id);
  final int id;
  @override
  bool operator ==(Object other) => other is RenameTab && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A11 D18: the tab whose one-line description field is open.
final class EditDescription extends RenameTarget {
  const EditDescription(this.id);
  final int id;
  @override
  bool operator ==(Object other) => other is EditDescription && other.id == id;
  @override
  int get hashCode => Object.hash('desc', id);
}

final class RenameWorkspace extends RenameTarget {
  const RenameWorkspace(this.id);
  final String id;
  @override
  bool operator ==(Object other) => other is RenameWorkspace && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

const Object _keep = Object();

@immutable
final class SidebarState {
  const SidebarState({
    required this.workspaces,
    required this.members,
    this.currentId = kDefaultWorkspaceId,
    this.renaming,
  });

  final List<Workspace> workspaces;

  /// Tab ids per workspace id, in sidebar order. Never mutated in place.
  final Map<String, List<int>> members;

  /// Where ⌘T opens a tab: the selected tab's workspace (UI-A2 §3.3).
  final String currentId;
  final RenameTarget? renaming;

  /// D10: headers only from two workspaces on.
  bool get showHeaders => workspaces.length > 1;

  Workspace get defaultWorkspace => workspaces.firstWhere((w) => w.isDefault);

  Workspace? workspace(String id) {
    for (final w in workspaces) {
      if (w.id == id) return w;
    }
    return null;
  }

  List<int> tabsOf(String id) => members[id] ?? const [];

  String? workspaceOf(int tabId) {
    for (final MapEntry(key: id, value: tabs) in members.entries) {
      if (tabs.contains(tabId)) return id;
    }
    return null;
  }

  /// A11 D19: the text size step of the workspace holding [tabId]; 0 for
  /// a tab not placed yet.
  double fontStepOf(int tabId) {
    final id = workspaceOf(tabId);
    return id == null ? 0 : workspace(id)?.fontStep ?? 0;
  }

  List<int> get orderedTabIds => [for (final w in workspaces) ...tabsOf(w.id)];

  /// What the sidebar shows, top to bottom; ⌘1–9, Ctrl+Tab and ↑/↓ follow
  /// it (C5). Collapsed only counts while headers show.
  List<int> get visibleTabIds => [
    for (final w in workspaces)
      if (!showHeaders || !w.collapsed) ...tabsOf(w.id),
  ];

  /// I2: which tab is selected when the selected tab [closed] goes (⌘W,
  /// an exit): the next visible tab in the sidebar, else the previous one.
  /// A hidden [closed] (its workspace collapsed) gives the nearest visible
  /// tab below it, else above it; with nothing visible, the next in
  /// [orderedTabIds], else the previous. Null: no other tab here.
  int? successorOf(int closed) {
    final visible = visibleTabIds;
    final at = visible.indexOf(closed);
    if (at >= 0) {
      if (at + 1 < visible.length) return visible[at + 1];
      return at > 0 ? visible[at - 1] : _orderedNeighbour(closed);
    }
    return _nearestVisible(closed, 1) ??
        _nearestVisible(closed, -1) ??
        _orderedNeighbour(closed);
  }

  /// The first visible tab after (or before, [delta] < 0) [id] in
  /// [orderedTabIds].
  int? _nearestVisible(int id, int delta) {
    final ordered = orderedTabIds;
    final visible = visibleTabIds.toSet();
    final at = ordered.indexOf(id);
    final ahead = delta > 0
        ? ordered.skip(at + 1)
        : ordered.take(max(at, 0)).toList().reversed;
    return ahead.where(visible.contains).firstOrNull;
  }

  int? _orderedNeighbour(int id) {
    final ordered = orderedTabIds;
    final at = ordered.indexOf(id);
    if (at < 0) return null;
    if (at + 1 < ordered.length) return ordered[at + 1];
    return at > 0 ? ordered[at - 1] : null;
  }

  SidebarState copyWith({
    List<Workspace>? workspaces,
    Map<String, List<int>>? members,
    String? currentId,
    Object? renaming = _keep,
  }) => SidebarState(
    workspaces: workspaces ?? this.workspaces,
    members: members ?? this.members,
    currentId: currentId ?? this.currentId,
    renaming: identical(renaming, _keep)
        ? this.renaming
        : renaming as RenameTarget?,
  );
}

/// A11 D19: the step of the workspace of the selected tab (0 with none);
/// Settings says its preview does not include it.
final selectedWorkspaceFontStepProvider = Provider<double>((ref) {
  final selected = ref.watch(terminalTabsProvider.select((s) => s.selectedId));
  final sidebar = ref.watch(sidebarWorkspacesProvider);
  return selected == null ? 0 : sidebar.fontStepOf(selected);
});

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => ref.watch(desktopServicesProvider).settings,
);

final sidebarWorkspacesProvider =
    NotifierProvider<SidebarWorkspaces, SidebarState>(SidebarWorkspaces.new);

/// Workspaces of the sidebar (spec C5, D10–D18). The list, names and
/// collapsed states are saved in the settings; which tab is where lives
/// only in memory (sessions end with the app until A5).
class SidebarWorkspaces extends Notifier<SidebarState> {
  final _random = Random();

  /// The next tab opened on this computer goes here (header `+`, ⌘⇧N),
  /// whatever is selected meanwhile; cleared once used.
  String? _pendingTarget;

  @override
  SidebarState build() {
    final stored = ref
        .watch(settingsStoreProvider)
        .getStrings(SettingKeys.terminalWorkspaces);
    ref.listen<TerminalTabsState>(
      terminalTabsProvider,
      (_, tabs) => state = _reconcile(state, tabs),
    );
    // I2: one place decides "which tab next", for a close too.
    final successor = ref.read(closeSuccessorProvider);
    int? choose(int closed) => state.successorOf(closed);
    successor.choose = choose;
    // A5a D10: restore's fallback selection only picks a tab one sees.
    final placement = ref.read(restorePlacementProvider);
    bool isShown(String? id) {
      final w = state.workspace(id ?? kDefaultWorkspaceId);
      return !state.showHeaders || !(w ?? state.defaultWorkspace).collapsed;
    }

    placement.isShown = isShown;
    bool hasWorkspace(String id) => state.workspace(id) != null;
    String currentWorkspace() => state.currentId;
    placement.hasWorkspace = hasWorkspace;
    placement.currentWorkspace = currentWorkspace;
    ref.onDispose(() {
      if (successor.choose == choose) successor.choose = null;
      if (placement.isShown == isShown) placement.isShown = null;
      if (placement.hasWorkspace == hasWorkspace) placement.hasWorkspace = null;
      if (placement.currentWorkspace == currentWorkspace) {
        placement.currentWorkspace = null;
      }
    });
    return _reconcile(
      SidebarState(workspaces: loadWorkspaces(stored), members: const {}),
      ref.read(terminalTabsProvider),
    );
  }

  AppLocalizations get _l10n => ref.read(appL10nProvider);
  TerminalTabs get _tabs => ref.read(terminalTabsProvider.notifier);

  String displayName(String id) =>
      state.workspace(id)?.displayName(_l10n) ?? '';

  /// D15: "Workspace N" at the end, current, its name field open; with a
  /// new tab in it, or with [moveTab] moved into it ("Move to workspace…
  /// → New workspace").
  Future<void> create({int? moveTab}) async {
    final id = _newId();
    state = state.copyWith(
      workspaces: [
        ...state.workspaces,
        Workspace(id: id, name: _numberedName()),
      ],
      members: {...state.members, id: const <int>[]},
      currentId: id,
      renaming: RenameWorkspace(id),
    );
    _save();
    if (moveTab != null) {
      this.moveTab(moveTab, id);
    } else {
      await openTabIn(id);
    }
  }

  /// A7 D22: a workspace for the command line — appended, named [name]
  /// (blank: "Workspace N"), saved; the current workspace stays and no
  /// name field opens. Returns its id.
  String createFor({String? name}) {
    final id = _newId();
    final clean = name?.trim() ?? '';
    state = state.copyWith(
      workspaces: [
        ...state.workspaces,
        Workspace(id: id, name: clean.isEmpty ? _numberedName() : _clip(clean)),
      ],
      members: {...state.members, id: const <int>[]},
    );
    _save();
    return id;
  }

  /// A7 D22: takes back a [createFor] workspace whose tab never came
  /// (no toast, unlike [delete]). Nothing when it holds a tab.
  void discard(String id) {
    final w = state.workspace(id);
    if (w == null || w.isDefault || state.tabsOf(id).isNotEmpty) return;
    state = state.copyWith(
      workspaces: [
        for (final x in state.workspaces)
          if (x.id != id) x,
      ],
      members: {
        for (final e in state.members.entries)
          if (e.key != id) e.key: e.value,
      },
      currentId: state.currentId == id ? kDefaultWorkspaceId : state.currentId,
      renaming: state.renaming == RenameWorkspace(id) ? null : state.renaming,
    );
    _save();
  }

  /// A8 D23: the first workspace (sidebar order) for server [key].
  String? workspaceForHost(String key) {
    for (final w in state.workspaces) {
      if (w.ssh == key) return w.id;
    }
    return null;
  }

  /// A8 D23: a workspace named after the server, at the end, no name
  /// field; current unless the command line made it ([makeCurrent] false).
  String createForHost(SshTarget target, {bool makeCurrent = true}) {
    final id = _newId();
    state = state.copyWith(
      workspaces: [
        ...state.workspaces,
        Workspace(id: id, name: _clip(target.key), ssh: target.key),
      ],
      members: {...state.members, id: const <int>[]},
      currentId: makeCurrent ? id : state.currentId,
    );
    _save();
    return id;
  }

  /// A8 D23: what a new tab in [workspaceId] runs; null: a local shell.
  SessionLaunch? launchFor(String workspaceId) {
    final key = state.workspace(workspaceId)?.ssh;
    final target = key == null ? null : SshTarget.parseKey(key);
    if (target == null) return null;
    return SshLaunch(
      target,
      hook: sshHookFor(
        ref.read(settingsStoreProvider),
        target.key,
        globalOn: ref.read(agentControllerProvider).sshRemoteHook,
      ),
    );
  }

  /// Header `+` (UI-A2 §3.1): a new tab in [id], which expands; in a
  /// server's workspace it opens that server ([launch] overrides).
  Future<void> openTabIn(String id, {SessionLaunch? launch}) async {
    if (state.workspace(id) == null) return;
    _pendingTarget = id;
    setCollapsed(id, false);
    try {
      await _tabs.openTab(launch: launch ?? launchFor(id));
    } finally {
      _pendingTarget = null;
    }
  }

  /// A8 UI-A8 §2.3 "New local tab" in a server's workspace: a shell on this
  /// computer, placed in [id] (expanded) like [openTabIn].
  Future<void> openLocalTabIn(String id) async {
    if (state.workspace(id) == null) return;
    _pendingTarget = id;
    setCollapsed(id, false);
    try {
      await _tabs.openTab();
    } finally {
      _pendingTarget = null;
    }
  }

  /// Blank keeps the old name (UI-A2 §4).
  void rename(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty || state.workspace(id) == null) return;
    state = state.copyWith(
      workspaces: [
        for (final w in state.workspaces)
          w.id == id ? w.copyWith(name: _clip(clean)) : w,
      ],
    );
    _save();
  }

  /// A11 D19: [delta] points more (or fewer) for every tab of workspace
  /// [id], kept within −6…+10 and saved with the workspace.
  void zoom(String id, double delta) {
    final w = state.workspace(id);
    if (w == null) return;
    _setFontStep(w, w.fontStep + delta);
  }

  void resetZoom(String id) {
    final w = state.workspace(id);
    if (w != null) _setFontStep(w, 0);
  }

  void _setFontStep(Workspace w, double step) {
    // A press never builds up a hidden step: global + step stays within
    // the 9-28 the text can be drawn at.
    final global = ref.read(terminalFontSizeProvider);
    final next = step
        .clamp(
          max(kWorkspaceFontStepMin, kTerminalFontSizeMin - global),
          min(kWorkspaceFontStepMax, kTerminalFontSizeMax - global),
        )
        .toDouble();
    if (next == w.fontStep) return;
    state = state.copyWith(
      workspaces: [
        for (final x in state.workspaces)
          x.id == w.id ? x.copyWith(fontStep: next) : x,
      ],
    );
    _save();
  }

  void toggleCollapsed(String id) {
    final w = state.workspace(id);
    if (w != null) setCollapsed(id, !w.collapsed);
  }

  void setCollapsed(String id, bool collapsed) {
    final w = state.workspace(id);
    if (w == null || w.collapsed == collapsed) return;
    state = state.copyWith(
      workspaces: [
        for (final x in state.workspaces)
          x.id == id ? x.copyWith(collapsed: collapsed) : x,
      ],
    );
    _save();
  }

  /// A4 D13/D16: the workspace holding [tabId] is expanded.
  void reveal(int tabId) {
    final id = state.workspaceOf(tabId);
    if (id != null) setCollapsed(id, false);
  }

  /// D16: no confirmation; the tabs go to the end of Default, which
  /// expands; a neutral toast says so. Default itself stays (D11).
  void delete(String id) {
    final w = state.workspace(id);
    if (w == null || w.isDefault) return;
    final moved = state.tabsOf(id);
    state = state.copyWith(
      workspaces: [
        for (final x in state.workspaces)
          if (x.id != id)
            x.isDefault && moved.isNotEmpty ? x.copyWith(collapsed: false) : x,
      ],
      members: {
        for (final e in state.members.entries)
          if (e.key != id)
            e.key: e.key == kDefaultWorkspaceId
                ? [...e.value, ...moved]
                : e.value,
      },
      currentId: state.currentId == id ? kDefaultWorkspaceId : state.currentId,
      renaming: state.renaming == RenameWorkspace(id) ? null : state.renaming,
    );
    _save();
    _tabs.showNotice(
      WorkspaceDeletedNotice(
        name: w.displayName(_l10n),
        movedTo: state.defaultWorkspace.displayName(_l10n),
      ),
    );
  }

  /// Moves [tabId] into [workspaceId] at [index], counted in the target
  /// list as it is before the move (null: the end). The target expands.
  void moveTab(int tabId, String workspaceId, [int? index]) {
    final from = state.workspaceOf(tabId);
    if (from == null || state.workspace(workspaceId) == null) return;
    var at = index ?? state.tabsOf(workspaceId).length;
    if (from == workspaceId && state.tabsOf(from).indexOf(tabId) < at) at--;
    final members = {
      for (final e in state.members.entries)
        e.key: [
          for (final id in e.value)
            if (id != tabId) id,
        ],
    };
    final target = members[workspaceId]!;
    // A11 D18: pinned tabs are the first of a workspace, others after.
    final pinnedCount = target.where(_isPinned).length;
    final isPinned = _isPinned(tabId);
    target.insert(
      isPinned
          ? at.clamp(0, pinnedCount)
          : at.clamp(pinnedCount, target.length),
      tabId,
    );
    final selected = ref.read(terminalTabsProvider).selectedId == tabId;
    state = state.copyWith(
      members: members,
      currentId: selected ? workspaceId : state.currentId,
    );
    setCollapsed(workspaceId, false);
  }

  bool canMoveUp(int tabId) => _neighbour(tabId, -1) != null;
  bool canMoveDown(int tabId) => _neighbour(tabId, 1) != null;
  void moveUp(int tabId) => _move(tabId, -1);
  void moveDown(int tabId) => _move(tabId, 1);

  void _move(int tabId, int step) {
    final to = _neighbour(tabId, step);
    if (to != null) moveTab(tabId, to.$1, to.$2);
  }

  /// Where one step moves [tabId] (workspace, index before the move), or
  /// null at the very top/bottom. Crosses a workspace boundary only while
  /// headers show.
  (String, int)? _neighbour(int tabId, int step) {
    final from = state.workspaceOf(tabId);
    if (from == null) return null;
    final list = state.tabsOf(from);
    final next = list.indexOf(tabId) + step;
    if (next >= 0 && next < list.length) {
      // A11 D18: one step never crosses between the pinned and the rest.
      if (_isPinned(list[next]) != _isPinned(tabId)) return null;
      return (from, step > 0 ? next + 1 : next);
    }
    if (!state.showHeaders) return null;
    final w = state.workspaces.indexWhere((x) => x.id == from) + step;
    if (w < 0 || w >= state.workspaces.length) return null;
    final target = state.workspaces[w].id;
    return (target, step > 0 ? 0 : state.tabsOf(target).length);
  }

  /// ⌘1…⌘9 (C5): the n-th visible tab; nothing when there is none.
  void selectVisible(int position) {
    final ids = state.visibleTabIds;
    if (position >= 1 && position <= ids.length) {
      _tabs.select(ids[position - 1]);
    }
  }

  /// Ctrl+Tab / ↑↓: the next visible tab, wrapping. From a hidden selected
  /// tab (its workspace collapsed), the nearest visible one that way.
  void step(int delta) {
    final visible = state.visibleTabIds;
    if (visible.isEmpty) return;
    final selected = ref.read(terminalTabsProvider).selectedId;
    final i = selected == null ? -1 : visible.indexOf(selected);
    if (i >= 0) {
      _tabs.select(visible[(i + delta) % visible.length]);
      return;
    }
    final next = selected == null
        ? null
        : state._nearestVisible(selected, delta);
    _tabs.select(next ?? (delta > 0 ? visible.first : visible.last));
  }

  /// A5a D1, D10: puts restored tabs in their saved order. Workspaces no
  /// longer in the settings send their tabs to the end of Default; tabs
  /// not mentioned keep their place. The selected tab's workspace becomes
  /// current. Nothing expands (criterion 1).
  void adopt(
    List<SavedWorkspace> workspaces,
    Map<String, int> tabIdByKey, {
    int? selectedTabId,
  }) {
    final moved = <int>{};
    final members = <String, List<int>>{
      for (final w in state.workspaces) w.id: <int>[],
    };
    final live = {for (final ids in state.members.values) ...ids};
    for (final saved in workspaces) {
      final target = members.containsKey(saved.id)
          ? saved.id
          : kDefaultWorkspaceId;
      for (final key in saved.tabs) {
        final id = tabIdByKey[key];
        if (id == null || !live.contains(id) || !moved.add(id)) continue;
        members[target]!.add(id);
      }
    }
    for (final w in state.workspaces) {
      members[w.id]!.addAll(
        state.tabsOf(w.id).where((id) => !moved.contains(id)),
      );
    }
    for (final w in members.keys) {
      members[w] = sortPinnedFirst(members[w]!, _isPinned);
    }
    final selectedIn = selectedTabId == null
        ? null
        : members.entries
              .where((e) => e.value.contains(selectedTabId))
              .firstOrNull
              ?.key;
    state = state.copyWith(
      members: members,
      currentId: selectedIn ?? state.currentId,
    );
  }

  bool _isPinned(int tabId) =>
      ref
          .read(terminalTabsProvider)
          .tabs
          .where((t) => t.id == tabId)
          .firstOrNull
          ?.meta
          .pinned ??
      false;

  void startRename(RenameTarget target) =>
      state = state.copyWith(renaming: target);

  void endRename() => state = state.copyWith(renaming: null);

  // ---- internals --------------------------------------------------------

  SidebarState _reconcile(SidebarState s, TerminalTabsState tabs) {
    final live = {for (final t in tabs.tabs) t.id: t};
    final members = <String, List<int>>{
      for (final w in s.workspaces)
        w.id: [
          for (final id in s.tabsOf(w.id))
            if (live.containsKey(id)) id,
        ],
    };
    final placed = {for (final ids in members.values) ...ids};
    final expand = <String>{};
    final restored = ref.read(restorePlacementProvider).pending;
    for (final tab in tabs.tabs) {
      if (placed.contains(tab.id)) continue;
      if (restored.containsKey(tab.id)) {
        // A5a criterion 1: back where it was saved, its workspace left
        // collapsed or expanded as the settings say.
        final saved = restored.remove(tab.id);
        members[saved != null && members.containsKey(saved)
                ? saved
                : kDefaultWorkspaceId]!
            .add(tab.id);
        continue;
      }
      if (tab.origin == SessionOrigin.phone) {
        members[kDefaultWorkspaceId]!.add(tab.id);
        continue;
      }
      final pending = _pendingTarget;
      final target = pending != null && members.containsKey(pending)
          ? pending
          : members.containsKey(s.currentId)
          ? s.currentId
          : kDefaultWorkspaceId;
      _pendingTarget = null;
      members[target]!.add(tab.id);
      expand.add(target); // a tab opened here is never born hidden
    }
    // A11 D18: pinned tabs lead their workspace, whatever changed.
    for (final w in members.keys.toList()) {
      members[w] = sortPinnedFirst(
        members[w]!,
        (id) => live[id]?.meta.pinned ?? false,
      );
    }
    var current = s.currentId;
    final selected = tabs.selectedId;
    if (selected != null) {
      for (final MapEntry(key: id, value: ids) in members.entries) {
        if (ids.contains(selected)) current = id;
      }
    }
    if (!members.containsKey(current)) current = kDefaultWorkspaceId;
    final renaming = switch (s.renaming) {
      RenameTab(:final id) when !live.containsKey(id) => null,
      EditDescription(:final id) when !live.containsKey(id) => null,
      final other => other,
    };
    final workspaces = expand.isEmpty
        ? s.workspaces
        : [
            for (final w in s.workspaces)
              expand.contains(w.id) ? w.copyWith(collapsed: false) : w,
          ];
    final next = s.copyWith(
      workspaces: workspaces,
      members: members,
      currentId: current,
      renaming: renaming,
    );
    if (!identical(workspaces, s.workspaces)) {
      scheduleMicrotask(_save);
    }
    return next;
  }

  String _newId() {
    String id;
    do {
      id = 'w${_random.nextInt(1 << 30).toRadixString(36)}';
    } while (state.workspace(id) != null);
    return id;
  }

  String _numberedName() {
    final used = {for (final w in state.workspaces) w.name};
    for (var n = 2; ; n++) {
      final name = _l10n.workspaceNumberedName(n);
      if (!used.contains(name)) return name;
    }
  }

  void _save() {
    if (!ref.mounted) return;
    final settings = ref.read(settingsStoreProvider);
    unawaited(
      settings
          .setStrings(SettingKeys.terminalWorkspaces, [
            for (final w in state.workspaces) w.encode(),
          ])
          .catchError(
            (Object e) => debugPrint('workspaces not saved: ${e.runtimeType}'),
          ),
    );
  }
}
