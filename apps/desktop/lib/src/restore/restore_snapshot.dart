import 'dart:convert';
import 'dart:math';

import 'package:shellx_agent/shellx_agent.dart' show SessionLaunch;

import '../terminal/agent_status.dart' show AgentKind, isValidSessionId;
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

/// V2-1 D14: an AI tab's agent id (`claude`, a custom agent's id).
final RegExp _agentId = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

/// V2-1 D14: an AI tab's saved title, at most this many characters.
const int _maxAiTitle = 200;
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

/// A12 D13: the agent that was running in a pane and its session, so a
/// restart can offer to resume it. [session] already matched
/// `kSessionId`.
typedef SavedAgent = ({AgentKind kind, String session});

/// The `agent` object of a saved pane: null for anything that is not a
/// known agent with a valid id (the pane still loads without it). Extra
/// keys are ignored.
SavedAgent? _agentFromJson(Object? raw) {
  if (raw is! Map<String, Object?>) return null;
  final k = raw['k'], s = raw['s'];
  if (k is! String || s is! String || !isValidSessionId(s)) return null;
  final kind = AgentKind.values.where((a) => a.name == k).firstOrNull;
  return kind == null ? null : (kind: kind, session: s);
}

final class SavedPane extends SavedPaneNode {
  const SavedPane({
    required this.key,
    this.cwd,
    this.session,
    this.launch,
    this.agent,
  });
  final String key;

  /// A12 D13, optional JSON key `agent`: written only when set and valid,
  /// so a plain layout is byte-identical to before and an older build
  /// ignores the key.
  final SavedAgent? agent;

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

/// V2-1 D14: one AI tab of `layout.json` (`aiTabs`). Its key is the key
/// of its AI leaf (`{"ai": key}`); ruling B3: that leaf is all the layout
/// holds. Never any conversation: the agent keeps it, under [session].
final class SavedAiTab {
  const SavedAiTab({
    required this.key,
    required this.title,
    required this.agent,
    required this.agentName,
    this.name,
    this.session,
    this.cwd,
    this.pinned = false,
    this.description = '',
    this.status = TabStatus.none,
  });

  final String key;

  /// The automatic title (the session's, or the first prompt).
  final String title;

  /// The user's name for the tab (B4); null: automatic.
  final String? name;
  final String agent;
  final String agentName;

  /// The agent's session id, already a valid A12 session id.
  final String? session;
  final String? cwd;
  final bool pinned;
  final String description;
  final TabStatus status;

  TabMeta get meta =>
      TabMeta(pinned: pinned, description: description, status: status);

  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'name': ?name,
    'focused': key,
    'zoomed': null,
    'agent': agent,
    'agentName': agentName,
    'session': session,
    'cwd': cwd,
    'layout': {'ai': key},
    if (pinned) 'pinned': true,
    if (description.isNotEmpty) 'desc': description,
    if (status != TabStatus.none) 'status': status.wire,
  };

  /// Null for anything that is not a well-formed AI tab: the entry is then
  /// dropped, never the file. Damaged optional fields are repaired.
  static SavedAiTab? tryParse(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final key = raw['key'];
    final agent = raw['agent'];
    if (key is! String || !isPaneKey(key)) return null;
    if (agent is! String || !_agentId.hasMatch(agent)) return null;
    if (!_hasAiLeaf(raw['layout'], key, 0)) return null;
    final title = raw['title'];
    final name = raw['name'];
    final agentName = raw['agentName'];
    final session = raw['session'];
    final cwd = raw['cwd'];
    return SavedAiTab(
      key: key,
      title: title is String ? _cleanTitle(title) : '',
      name: name is String && name.isNotEmpty && name.length <= _maxName
          ? name
          : null,
      agent: agent,
      agentName:
          agentName is String &&
              agentName.trim().isNotEmpty &&
              agentName.length <= _maxName
          ? agentName
          : agent,
      session: session is String && isValidSessionId(session) ? session : null,
      cwd: cwd is String && isRestorableCwd(cwd) ? cwd : null,
      pinned: raw['pinned'] == true,
      description: switch (raw['desc']) {
        final String d => TabMeta.cleanDescription(d),
        _ => '',
      },
      status: TabStatus.fromWire(raw['status']),
    );
  }

  static bool _hasAiLeaf(Object? node, String key, int depth) {
    if (depth > _maxDepth || node is! Map<String, Object?>) return false;
    if (node['ai'] == key) return true;
    return _hasAiLeaf(node['first'], key, depth + 1) ||
        _hasAiLeaf(node['second'], key, depth + 1);
  }

  static String _cleanTitle(String text) {
    final clean = text.replaceAll(_control, ' ').trim();
    final runes = clean.runes;
    return runes.length <= _maxAiTitle
        ? clean
        : String.fromCharCodes(runes.take(_maxAiTitle));
  }
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
    this.aiTabs = const [],
  });

  final DateTime savedAt;
  final bool cleanExit;

  /// D21: the A5b daemon instance; always null in A5a.
  final String? daemon;
  final String? selectedTab;
  final List<SavedWorkspace> workspaces;
  final List<SavedTab> tabs;

  /// V2-1 D14: the AI tabs (top-level `aiTabs`, which V1 ignores).
  final List<SavedAiTab> aiTabs;

  /// Something to restore: a terminal tab or an AI tab (Review Focus 2).
  bool get hasTabs => tabs.isNotEmpty || aiTabs.isNotEmpty;

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
        aiTabs: aiTabs,
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
    // V2-1 D14: only when there is one, so a terminal-only layout is
    // byte-identical to before.
    if (aiTabs.isNotEmpty) 'aiTabs': [for (final t in aiTabs) t.toJson()],
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
      // V2-1 D14: the AI tabs; a damaged one is dropped, never the file.
      final aiTabs = <SavedAiTab>[];
      final aiKeys = <String>{};
      if (root['aiTabs'] case final List<Object?> list) {
        for (final raw in list) {
          final t = SavedAiTab.tryParse(raw);
          if (t == null || tabKeys.contains(t.key) || seen.contains(t.key)) {
            continue;
          }
          if (aiKeys.add(t.key)) aiTabs.add(t);
        }
      }
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
          if (tabKeys.contains(key) || aiKeys.contains(key)) {
            members.add(key);
          }
        }
        workspaces.add(SavedWorkspace(id: id, tabs: members));
      }
      final selected = root['selectedTab'] as String?;
      return RestoreSnapshot(
        savedAt: savedAt,
        cleanExit: clean,
        daemon: root['daemon'] as String?,
        selectedTab: tabKeys.contains(selected) || aiKeys.contains(selected)
            ? selected
            : null,
        workspaces: workspaces,
        tabs: tabs,
        aiTabs: aiTabs,
      );
    } on Object {
      // FormatException, TypeError from a cast, ArgumentError from
      // `byName`: not a file we wrote.
      return null;
    }
  }
}

Object _nodeToJson(SavedPaneNode node) => switch (node) {
  SavedPane(
    :final key,
    :final cwd,
    :final session,
    :final launch,
    :final agent,
  ) =>
    {
      'pane': key,
      'cwd': cwd,
      'session': session,
      if (launch != null) 'launch': launch.toJson(),
      if (agent != null && isValidSessionId(agent.session))
        'agent': {'k': agent.kind.name, 's': agent.session},
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
    return SavedPane(
      key: key,
      cwd: cwd,
      session: session,
      launch: launch,
      // Repaired, never fatal: a damaged agent must not lose a layout.
      agent: _agentFromJson(m['agent']),
    );
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
