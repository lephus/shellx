import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_engine.dart';
import '../browser/engines/win_floating_engine.dart';
import '../browser/engines/wk_webview_engine.dart';
import '../config/config_controller.dart';
import '../config/keybindings.dart';
import '../terminal/terminal_tabs.dart';
import 'tool_dock.dart';
import 'tool_embed.dart';
import 'tool_entry.dart';
import 'tool_keys.dart';
import 'tool_navigation.dart';
import 'tool_page.dart';
import 'tool_registry.dart';

/// D5 (A6 D28): at most this many live pages in the whole app.
const int kMaxLiveToolPages = 8;

/// Makes the engine of [tool]'s page; [dialogs] shows its JavaScript
/// dialogs. Tests swap it for `FakeBrowserEngine`.
typedef ToolEngineFactory =
    BrowserEngine Function(ToolEntry tool, BrowserDialogPresenter dialogs);

final toolEngineFactoryProvider = Provider<ToolEngineFactory>(
  (ref) =>
      (tool, dialogs) => Platform.isWindows
      ? WinFloatingEngine(
          policy: toolNavigation,
          dataFolder: toolDataFolder(Platform.environment) ?? '',
        )
      : WkWebViewEngine(
          native: ref.read(browserNativeMacProvider),
          policy: toolNavigation,
          dialogs: dialogs,
        ),
);

/// D8, D22: the data store every tool shares ("Clear tool data…").
final toolDataStoreProvider = Provider<BrowserDataStore>(
  (ref) => Platform.isWindows
      ? WinFloatingDataStore(toolDataFolder(Platform.environment))
      : ref.read(browserNativeMacProvider),
);

/// Ruling R9's knock; tests make it a fake.
final toolKnockProvider = Provider<ToolKnock>((ref) => knockToolPort);

final toolPagesProvider = NotifierProvider<ToolPages, Set<String>>(
  ToolPages.new,
);

/// V2-3 D5: the live pages, by tool id (the state is the set of ids, so a
/// dock rebuilds when a page comes or goes). A page is made when its dock
/// first shows it; past [kMaxLiveToolPages] the page unseen longest is
/// unloaded (its chip stays, a toast says so). A closed chip, a deleted
/// tool or a new URL (D23) reaches its page here; so does `tool-embed`
/// turning off (D20).
class ToolPages extends Notifier<Set<String>> {
  final _pages = <String, ToolPage>{};

  /// Least recently shown first.
  final _order = <String>[];

  @override
  Set<String> build() {
    ref.listen<List<ToolEntry>>(toolRegistryProvider, (_, tools) {
      final byId = {for (final t in tools) t.id: t};
      for (final id in [..._pages.keys]) {
        final tool = byId[id];
        if (tool == null) {
          close(id);
        } else if (!identical(tool, _pages[id]!.tool)) {
          _pages[id]!.retarget(tool);
        }
      }
    });
    ref.listen<ToolDocks>(toolDockProvider, (_, docks) {
      final open = {for (final d in docks.byWorkspace.values) ...d.tools};
      for (final id in [..._pages.keys]) {
        if (!open.contains(id)) close(id);
      }
    });
    // D20: tools no longer shown in ShellX (`tool-embed = off`) leave no
    // page running hidden — no UI would be left to stop its scripts,
    // sockets or audio. The chips stay; shown again, a page loads again
    // (R15).
    ref.listen<bool>(toolsEmbeddedProvider, (_, embedded) {
      if (embedded) return;
      for (final id in [..._pages.keys]) {
        close(id);
      }
    });
    ref.listen<KeyBindings>(shellxConfigProvider.select((s) => s.bindings), (
      _,
      bindings,
    ) {
      final chords = toolForwardedChords(bindings);
      for (final page in _pages.values) {
        unawaited(page.engine.setForwardedChords(chords));
      }
    });
    ref.onDispose(() {
      for (final page in _pages.values) {
        page.dispose();
      }
      _pages.clear();
      _order.clear();
    });
    return const {};
  }

  ToolPage? existing(String toolId) => _pages[toolId];

  /// [tool]'s page, made (not loaded: [ToolPage.setShown] loads it) on the
  /// first call. Never call it while building.
  ToolPage open(ToolEntry tool) {
    final made = _pages[tool.id];
    if (made != null) {
      _touch(tool.id);
      return made;
    }
    final factory = ref.read(toolEngineFactoryProvider);
    final page = ToolPage(
      tool: tool,
      engine: (dialogs) => factory(tool, dialogs),
      knock: ref.read(toolKnockProvider),
    );
    unawaited(
      page.engine.setForwardedChords(
        toolForwardedChords(ref.read(shellxConfigProvider).bindings),
      ),
    );
    _pages[tool.id] = page;
    _touch(tool.id);
    _evict();
    state = {..._pages.keys};
    return page;
  }

  /// The page leaves (its chip closed, its tool deleted).
  void close(String toolId) {
    final page = _pages.remove(toolId);
    if (page == null) return;
    _order.remove(toolId);
    page.dispose();
    state = {..._pages.keys};
  }

  void _touch(String id) {
    _order
      ..remove(id)
      ..add(id);
  }

  void _evict() {
    while (_pages.length > kMaxLiveToolPages) {
      final victim = _order.firstWhere(
        (id) => !(_pages[id]?.shown ?? false),
        orElse: () => _order.first,
      );
      final name = _pages[victim]?.tool.name ?? '';
      close(victim);
      ref
          .read(terminalTabsProvider.notifier)
          .showNotice(ToolUnloadedNotice(name));
    }
  }

  @override
  String toString() => 'ToolPages(${_pages.length})';
}
