import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/settings_store.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import 'tool_entry.dart';

/// D2: a new tool's id — 10 random `[a-z0-9]`. Tests swap it for a
/// counter.
final toolIdSourceProvider = Provider<String Function()>((ref) {
  final random = Random.secure();
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return () => List.generate(
    10,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
});

final toolRegistryProvider = NotifierProvider<ToolRegistry, List<ToolEntry>>(
  ToolRegistry.new,
);

/// V2-3 D2: every tool of every workspace, in the order they were added,
/// kept in [SettingKeys.workspaceTools] (one JSON object per element, a
/// window-owned key) — never inside the workspace JSON, which an older
/// build rewrites without the keys it does not know.
class ToolRegistry extends Notifier<List<ToolEntry>> {
  @override
  List<ToolEntry> build() {
    final stored = ref
        .watch(settingsStoreProvider)
        .getStrings(SettingKeys.workspaceTools);
    final result = <ToolEntry>[];
    final ids = <String>{};
    final perWorkspace = <String, int>{};
    for (final text in stored) {
      Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        continue; // a damaged entry goes, the others stay (§8)
      }
      final tool = ToolEntry.fromJson(json);
      if (tool == null || !ids.add(tool.id)) continue;
      final count = perWorkspace[tool.ws] ?? 0;
      if (count >= kMaxToolsPerWorkspace) continue;
      perWorkspace[tool.ws] = count + 1;
      result.add(tool);
    }
    return List.unmodifiable(result);
  }

  /// D1, D2, D15: a new tool at the end of [ws]'s list. Null when [url]
  /// is not a tool URL ([parseToolUrl]) or [ws] already has
  /// [kMaxToolsPerWorkspace] tools. A blank [name] becomes `host:port`;
  /// [phone] holds only for a tool that may open on a phone.
  ToolEntry? add({
    required String ws,
    required String name,
    required String url,
    bool phone = false,
  }) {
    if (ws.isEmpty || inWorkspace(ws).length >= kMaxToolsPerWorkspace) {
      return null;
    }
    final parsed = parseToolUrl(url);
    if (parsed is! ToolUrlOk) return null;
    final draft = ToolEntry(
      id: _newId(),
      ws: ws,
      name: toolNameFor(name, parsed.url),
      url: parsed.url,
    );
    final tool = draft.copyWith(phone: phone && draft.phoneAllowed);
    state = List.unmodifiable([...state, tool]);
    _save();
    return tool;
  }

  /// D23: the name, URL and phone flag of the tool with [entry]'s id; its
  /// workspace and place stay. Nothing for an unknown id or a URL that is
  /// not a tool URL.
  void update(ToolEntry entry) {
    final at = state.indexWhere((t) => t.id == entry.id);
    if (at < 0) return;
    final parsed = parseToolUrl(entry.url);
    if (parsed is! ToolUrlOk) return;
    final old = state[at];
    final next = ToolEntry(
      id: old.id,
      ws: old.ws,
      name: toolNameFor(entry.name, parsed.url),
      url: parsed.url,
    );
    final tool = next.copyWith(phone: entry.phone && next.phoneAllowed);
    if (tool.name == old.name &&
        tool.url == old.url &&
        tool.phone == old.phone) {
      return;
    }
    state = List.unmodifiable([...state]..[at] = tool);
    _save();
  }

  void remove(String id) {
    if (!state.any((t) => t.id == id)) return;
    state = List.unmodifiable([
      for (final t in state)
        if (t.id != id) t,
    ]);
    _save();
  }

  /// D2: a deleted workspace takes its tools with it.
  void removeWorkspace(String ws) {
    if (!state.any((t) => t.ws == ws)) return;
    state = List.unmodifiable([
      for (final t in state)
        if (t.ws != ws) t,
    ]);
    _save();
  }

  ToolEntry? byId(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<ToolEntry> inWorkspace(String ws) => [
    for (final t in state)
      if (t.ws == ws) t,
  ];

  String _newId() {
    final next = ref.read(toolIdSourceProvider);
    for (;;) {
      final id = next();
      if (kToolIdPattern.hasMatch(id) && byId(id) == null) return id;
    }
  }

  void _save() {
    if (!ref.mounted) return;
    final settings = ref.read(settingsStoreProvider);
    unawaited(
      settings
          .setStrings(SettingKeys.workspaceTools, [
            for (final t in state) jsonEncode(t.toJson()),
          ])
          .catchError(
            (Object e) => debugPrint('tools not saved: ${e.runtimeType}'),
          ),
    );
  }

  @override
  String toString() => 'ToolRegistry(…)';
}
