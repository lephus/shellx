import 'dart:convert';
import 'dart:math';

import 'package:shellx_agent/shellx_agent.dart' show SessionLaunch;

import '../terminal/pane_layout.dart';
import '../terminal/tab_meta.dart';

// Pure model of `restore/layout.json`: imports only the A3 pane tree, so
// the tab and sidebar notifiers can depend on it without a cycle. Capture
// from live state lives in `restore_capture.dart`.

const int _version = 1;
const int _maxPanes = 32;
const int _maxDepth = 32;
const int _maxName = 64;
const int _maxCwd = 4096;

/// Same bound as A2's stored workspace ids (`Workspace.decode`).
const int _maxWorkspaceId = 64;
final RegExp _keyPattern = RegExp(r'^[0-9a-f]{32}$');

/// POSIX `/…`, Windows `C:\…` or `C:/…`, or UNC `\\…`.
final RegExp _absolutePath = RegExp(r'^(/|[A-Za-z]:[\\/]|\\\\)');

/// C0, DEL and C1 controls (NUL included).
final RegExp _control = RegExp(r'[\x00-\x1f\x7f-\x9f]');

/// Whether [cwd] passes the load check (D11): absolute, ≤ 4096 characters,
/// no control characters. Capture writes null for anything else so its
/// own output always loads.
bool isRestorableCwd(String cwd) =>
    cwd.length <= _maxCwd &&
    _absolutePath.hasMatch(cwd) &&
    !_control.hasMatch(cwd);

/// D14: a pane's restore key, never derived from user data.
String newPaneKey([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

bool isPaneKey(String text) => _keyPattern.hasMatch(text);

sealed class SavedPaneNode {
  const SavedPaneNode();
}

final class SavedPane extends SavedPaneNode {
  const SavedPane({required this.key, this.cwd, this.session, this.launch});
  final String key;

  /// The folder of a local pane; null for a remote one (its folder travels
  /// in [launch]).
  final String? cwd;

  /// A8 D29: how an SSH or tmux pane is reopened; null for a local shell.

  final SessionLaunch? launch;

  /// D21: written for A5b, ignored by A5a on load.
  final int? session;
}

final class SavedSplit extends SavedPaneNode {
  const SavedSplit({
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
  });
  final SplitAxis axis;
  final double ratio;
  final SavedPaneNode first, second;
}

/// The leaves of [node] in reading order (A3 D23).
List<SavedPane> savedLeaves(SavedPaneNode node) => switch (node) {
  SavedPane() => [node],
  SavedSplit(:final first, :final second) => [
    ...savedLeaves(first),
    ...savedLeaves(second),
  ],
};

final class SavedTab {
  const SavedTab({
    required this.key,
    this.name,
    required this.focused,
    this.zoomed,
    required this.layout,
    this.pinned = false,
    this.description = '',
    this.status = TabStatus.none,
  });

  /// The key of the pane that created the tab (A3 D1). When that pane has
  /// since closed or exited, the key stays the same and is no longer a
  /// leaf of [layout]: stable, and still unique among tabs.
  final String key;

  /// The custom title; null: automatic.
  final String? name;
  final String focused;
  final String? zoomed;
  final SavedPaneNode layout;

  /// A11 D18, optional keys `pinned`, `desc`, `status`: written only when
  /// not the default, so an older build ignores them and a plain layout is
  /// byte-identical to before.
  final bool pinned;
  final String description;
  final TabStatus status;

  TabMeta get meta =>
      TabMeta(pinned: pinned, description: description, status: status);
}

final class SavedWorkspace {
  const SavedWorkspace({required this.id, required this.tabs});

  /// The A2 workspace id (the names live in settings, D1).
  final String id;

  /// Tab keys in sidebar order.
  final List<String> tabs;
}

/// `restore/layout.json` v1 (spec §3.1).
final class RestoreSnapshot {
  const RestoreSnapshot({
    required this.savedAt,
    required this.cleanExit,
    this.daemon,
    this.selectedTab,
    required this.workspaces,
    required this.tabs,
  });

  final DateTime savedAt;
  final bool cleanExit;

  /// D21: the A5b daemon instance; always null in A5a.
  final String? daemon;
  final String? selectedTab;
  final List<SavedWorkspace> workspaces;
  final List<SavedTab> tabs;

  Set<String> get paneKeys => {
    for (final t in tabs) ...savedLeaves(t.layout).map((p) => p.key),
  };

  RestoreSnapshot copyWith({DateTime? savedAt, bool? cleanExit}) =>
      RestoreSnapshot(
        savedAt: savedAt ?? this.savedAt,
        cleanExit: cleanExit ?? this.cleanExit,
        daemon: daemon,
        selectedTab: selectedTab,
        workspaces: workspaces,
        tabs: tabs,
      );

  /// Equal apart from [savedAt] and [cleanExit]: no write needed.
  bool sameLayoutAs(RestoreSnapshot other) =>
      jsonEncode(_body()) == jsonEncode(other._body());

  Map<String, Object?> _body() => {
    'daemon': daemon,
    'selectedTab': selectedTab,
    'workspaces': [
      for (final w in workspaces) {'id': w.id, 'tabs': w.tabs},
    ],
    'tabs': [
      for (final t in tabs)
        {
          'key': t.key,
          'name': t.name,
          'focused': t.focused,
          'zoomed': t.zoomed,
          'layout': _nodeToJson(t.layout),
          if (t.pinned) 'pinned': true,
          if (t.description.isNotEmpty) 'desc': t.description,
          if (t.status != TabStatus.none) 'status': t.status.wire,
        },
    ],
  };

  String encode() => jsonEncode({
    'v': _version,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'cleanExit': cleanExit,
    ..._body(),
  });

  /// Null for anything that is not a well-formed v1 file (D11). Unknown
  /// keys are ignored so a later version's extra fields never break this.
  static RestoreSnapshot? tryParse(String text) {
    try {
      final root = jsonDecode(text);
      if (root is! Map<String, Object?> || root['v'] != _version) return null;
      final savedAt = DateTime.tryParse(root['savedAt'] as String? ?? '');
      final clean = root['cleanExit'];
      if (savedAt == null || clean is! bool) return null;
      final seen = <String>{};
      final tabs = <SavedTab>[];
      final tabKeys = <String>{};
      for (final raw in root['tabs']! as List<Object?>) {
        final t = raw! as Map<String, Object?>;
        final layout = _nodeFromJson(t['layout'], seen, 0);
        final keys = savedLeaves(layout).map((p) => p.key).toSet();
        final key = t['key']! as String;
        final focused = t['focused']! as String;
        final zoomed = t['zoomed'] as String?;
        final name = t['name'] as String?;
        if (!isPaneKey(key) || !tabKeys.add(key)) return null;
        if (!keys.contains(focused)) return null;
        if (zoomed != null && !keys.contains(zoomed)) return null;
        if (name != null && (name.isEmpty || name.length > _maxName)) {
          return null;
        }
        tabs.add(
          SavedTab(
            key: key,
            name: name,
            focused: focused,
            zoomed: zoomed,
            layout: layout,
            // Repaired, never fatal: a damaged marker must not lose a
            // whole layout.
            pinned: t['pinned'] == true,
            description: switch (t['desc']) {
              final String d => TabMeta.cleanDescription(d),
              _ => '',
            },
            status: TabStatus.fromWire(t['status']),
          ),
        );
      }
      if (seen.length > _maxPanes) return null;
      // A tab key is its creating pane's key: a leaf of its own tree, or
      // of none once that pane closed, never a pane of another tab.
      for (final t in tabs) {
        if (seen.contains(t.key) &&
            !savedLeaves(t.layout).any((p) => p.key == t.key)) {
          return null;
        }
      }
      final workspaces = <SavedWorkspace>[];
      final workspaceIds = <String>{};
      final listed = <String>{};
      for (final raw in root['workspaces']! as List<Object?>) {
        final w = raw! as Map<String, Object?>;
        final id = w['id'];
        if (id is! String || id.isEmpty || id.length > _maxWorkspaceId) {
          return null;
        }
        if (!workspaceIds.add(id)) return null;
        final members = <String>[];
        for (final k in w['tabs']! as List<Object?>) {
          // A tab sits in one place: once across all workspaces.
          final key = k! as String;
          if (!listed.add(key)) return null;
          if (tabKeys.contains(key)) members.add(key);
        }
        workspaces.add(SavedWorkspace(id: id, tabs: members));
      }
      final selected = root['selectedTab'] as String?;
      return RestoreSnapshot(
        savedAt: savedAt,
        cleanExit: clean,
        daemon: root['daemon'] as String?,
        selectedTab: tabKeys.contains(selected) ? selected : null,
        workspaces: workspaces,
        tabs: tabs,
      );
    } on Object {
      // FormatException, TypeError from a cast, ArgumentError from
      // `byName`: not a file we wrote.
      return null;
    }
  }
}

Object _nodeToJson(SavedPaneNode node) => switch (node) {
  SavedPane(:final key, :final cwd, :final session, :final launch) => {
    'pane': key,
    'cwd': cwd,
    'session': session,
    if (launch != null) 'launch': launch.toJson(),
  },
  SavedSplit(:final axis, :final ratio, :final first, :final second) => {
    'split': axis.name,
    'ratio': ratio,
    'first': _nodeToJson(first),
    'second': _nodeToJson(second),
  },
};

SavedPaneNode _nodeFromJson(Object? raw, Set<String> seen, int depth) {
  if (depth > _maxDepth) throw const FormatException('too deep');
  final m = raw! as Map<String, Object?>;
  if (m.containsKey('pane')) {
    final key = m['pane']! as String;
    final cwd = m['cwd'] as String?;
    if (!isPaneKey(key) || !seen.add(key)) {
      throw const FormatException('pane key');
    }
    if (cwd != null && !isRestorableCwd(cwd)) {
      throw const FormatException('cwd');
    }
    final session = m['session'] as int?;
    if (session != null && session <= 0) {
      throw const FormatException('session');
    }
    final rawLaunch = m['launch'];
    final launch = rawLaunch == null ? null : SessionLaunch.fromJson(rawLaunch);
    if (rawLaunch != null && launch == null) {
      // Never carries the value: it names a host.
      throw const FormatException('launch');
    }
    return SavedPane(key: key, cwd: cwd, session: session, launch: launch);
  }
  final axis = SplitAxis.values.byName(m['split']! as String);
  final ratio = (m['ratio']! as num).toDouble();
  if (ratio < kMinPaneRatio || ratio > 1 - kMinPaneRatio) {
    throw const FormatException('ratio');
  }
  return SavedSplit(
    axis: axis,
    ratio: ratio,
    first: _nodeFromJson(m['first'], seen, depth + 1),
    second: _nodeFromJson(m['second'], seen, depth + 1),
  );
}

/// The saved tree with each pane replaced by its new session; panes that
/// could not be reopened are dropped and their sibling takes the place
/// (A3 D7). Null when no pane is left.
PaneNode? buildLayout(SavedPaneNode node, Map<String, int> sessionByKey) =>
    switch (node) {
      SavedPane(:final key) => switch (sessionByKey[key]) {
        final id? => PaneLeaf(id),
        null => null,
      },
      SavedSplit(:final axis, :final ratio, :final first, :final second) =>
        _join(
          axis,
          ratio,
          buildLayout(first, sessionByKey),
          buildLayout(second, sessionByKey),
        ),
    };

PaneNode? _join(SplitAxis axis, double ratio, PaneNode? a, PaneNode? b) {
  if (a == null) return b;
  if (b == null) return a;
  return PaneSplit(axis: axis, ratio: ratio, first: a, second: b);
}
