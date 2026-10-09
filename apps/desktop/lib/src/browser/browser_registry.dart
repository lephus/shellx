import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/terminal_tabs.dart';
import 'browser_controller.dart';
import 'browser_engine.dart';
import 'browser_url.dart';

/// Builds the platform engine for one pane (Tasks 7, 8); overridden in
/// `main.dart` and in tests.
typedef BrowserEngineFactory = BrowserEngine Function(int paneId);

final browserEngineFactoryProvider = Provider<BrowserEngineFactory>(
  (ref) => throw StateError('browserEngineFactoryProvider must be overridden'),
);

/// D20: read at every agent call. Task 6 makes it read the setting.
final browserAllowAnyOriginProvider = Provider<bool Function()>(
  (ref) =>
      () => false,
);

final class BrowserShortcut {
  const BrowserShortcut(this.paneId, this.chord);
  final int paneId;
  final String chord;
}

final browserRegistryProvider = NotifierProvider<BrowserRegistry, Set<int>>(
  BrowserRegistry.new,
);

/// The live [BrowserController]s by pane id (state = their ids). A pane
/// gets its engine when its tab is first selected or when something asks
/// for it ([controller], A7) — so a restored workspace does not start
/// eight pages at once (D29). Removed panes are disposed (D34).
final class BrowserRegistry extends Notifier<Set<int>> {
  final Map<int, BrowserController> _controllers = {};
  final StreamController<BrowserNotice> _notices = StreamController.broadcast();
  final StreamController<BrowserShortcut> _shortcuts =
      StreamController.broadcast();
  final StreamController<int> _clicks = StreamController.broadcast();

  Stream<BrowserNotice> get notices => _notices.stream;
  Stream<BrowserShortcut> get shortcuts => _shortcuts.stream;
  Stream<int> get contentClicks => _clicks.stream;

  @override
  Set<int> build() {
    ref.listen(terminalTabsProvider, (_, next) => _sync(next));
    ref.onDispose(() {
      for (final c in _controllers.values) {
        unawaited(c.dispose());
      }
      _controllers.clear();
      _notices.close();
      _shortcuts.close();
      _clicks.close();
    });
    // Not during build: creating a controller writes to terminalTabs.
    scheduleMicrotask(() {
      if (ref.mounted) _sync(ref.read(terminalTabsProvider));
    });
    return const {};
  }

  /// The controller if it exists; never creates one (pane views of hidden
  /// tabs are built inside A3's IndexedStack and must not start engines).
  BrowserController? existing(int paneId) => _controllers[paneId];

  /// The pane's controller, creating it (and loading its page) when the
  /// pane exists but was never shown; `null` for an unknown pane.
  BrowserController? controller(int paneId) {
    final existing = _controllers[paneId];
    if (existing != null) return existing;
    final initial = ref
        .read(terminalTabsProvider)
        .tabOfPane(paneId)
        ?.browsers[paneId];
    if (initial == null) return null;
    final controller = BrowserController(
      paneId: paneId,
      engine: ref.read(browserEngineFactoryProvider)(paneId),
      initialUrl: initial.url,
      allowAnyOrigin: ref.read(browserAllowAnyOriginProvider),
      onState: (s) =>
          ref.read(terminalTabsProvider.notifier).updateBrowser(paneId, s),
      onNotice: _notices.add,
      onShortcut: (chord) => _shortcuts.add(BrowserShortcut(paneId, chord)),
      onContentClicked: () => _clicks.add(paneId),
    );
    _controllers[paneId] = controller;
    if (initial.url != aboutBlank) {
      scheduleMicrotask(() {
        if (_controllers[paneId] == controller) {
          unawaited(controller.navigate(initial.url));
        }
      });
    }
    scheduleMicrotask(() {
      if (ref.mounted) state = _controllers.keys.toSet();
    });
    return controller;
  }

  void _sync(TerminalTabsState tabs) {
    final live = {for (final t in tabs.tabs) ...t.browsers.keys};
    var changed = false;
    for (final id in _controllers.keys.toList()) {
      if (!live.contains(id)) {
        unawaited(_controllers.remove(id)!.dispose());
        changed = true;
      }
    }
    for (final id in tabs.selected?.browsers.keys ?? const <int>[]) {
      if (!_controllers.containsKey(id)) {
        controller(id);
        changed = true;
      }
    }
    if (changed) state = _controllers.keys.toSet();
  }
}
