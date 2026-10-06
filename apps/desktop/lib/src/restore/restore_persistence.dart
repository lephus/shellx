import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/desktop_services.dart' show clockProvider;
import '../platform/settings_store.dart';
import '../terminal/local_sessions_provider.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'restore_capture.dart';
import 'restore_snapshot.dart';
import 'restore_store.dart';
import 'scrollback_codec.dart';

/// The restore files. Stores nothing until main wires a [RestoreStore],
/// so widget tests that never wire one keep working.
final restoreStoreProvider = Provider<RestoreFiles>(
  (ref) => const NullRestoreFiles(),
);

/// UI-A5 §4: the abnormal-end strip.
final class RestoreStripState {
  const RestoreStripState({required this.tabs, this.contentsAt});

  /// How many tabs were restored.
  final int tabs;

  /// The newest saved-content time; null when no content was restored.
  final DateTime? contentsAt;
}

/// The abnormal-end strip to show (null: none). The UI watches this;
/// [RestorePersistence] sets it after a startup restore.
final restoreStripProvider = NotifierProvider<RestoreStrip, RestoreStripState?>(
  RestoreStrip.new,
);

class RestoreStrip extends Notifier<RestoreStripState?> {
  @override
  RestoreStripState? build() => null;

  void show(RestoreStripState strip) => state = strip;

  void dismiss() => state = null;
}

final restorePersistenceProvider = NotifierProvider<RestorePersistence, void>(
  RestorePersistence.new,
);

/// A5a: keeps `restore/` in step with the window (D4, D12–D15) and rebuilds
/// the window from it at startup (D7–D16, D23). Building it does nothing:
/// timers and listeners start in [start], which main calls (P1), so widget
/// tests that touch it run no timer.
class RestorePersistence extends Notifier<void> {
  static const layoutDebounce = Duration(seconds: 1);
  static const scrollbackPeriod = Duration(seconds: 60);

  /// D14: session id → pane key. Kept while the session is a live pane or
  /// the id of a live tab (a tab keeps the id of the pane that created it,
  /// A3 D1, and its key with it).
  final _keys = <int, String>{};

  /// Pane keys that may have a scrollback file. One that is no longer a
  /// pane of the layout loses its file at the next layout write (D15).
  final _filed = <String>{};

  /// Keys whose files go once a layout without them is on disk.
  final _doomed = <String>{};

  /// Sessions with output since their last save (D4).
  final _dirty = <int>{};

  Timer? _debounce;
  Timer? _period;

  /// The last layout on disk; null before the first write and after a
  /// failed one (§5: the next save retries).
  RestoreSnapshot? _written;
  bool _started = false;
  bool _restoring = false;

  /// Set by `flushAll(clean: true)`: what Quit saved is final (D12); the
  /// shutdown that follows must not overwrite or delete it.
  bool _frozen = false;

  RestoreFiles get _files => ref.read(restoreStoreProvider);
  SettingsStore get _settings => ref.read(settingsStoreProvider);

  /// D13: "Lưu nội dung terminal khi thoát".
  bool get scrollbackEnabled => _settings.getBool(
    SettingKeys.terminalRestoreScrollback,
    defaultValue: true,
  );

  @override
  void build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _period?.cancel();
    });
  }

  /// Starts following the window: layout changes (1 s debounce), pane
  /// output (saved every 60 s). Called once, by main.
  void start() {
    if (_started) return;
    _started = true;
    final outputs = ref
        .read(terminalTabsProvider.notifier)
        .paneOutputs
        .listen(_dirty.add);
    ref.onDispose(() => unawaited(outputs.cancel()));
    ref.listen(terminalTabsProvider, (_, _) => _schedule());
    ref.listen(sidebarWorkspacesProvider, (_, _) => _schedule());
    _period = Timer.periodic(scrollbackPeriod, (_) => _tick());
  }

  /// D14: a key per pane, made when the pane is first seen.
  String keyOf(int sessionId) => _keys.putIfAbsent(sessionId, () {
    final key = newPaneKey();
    _filed.add(key);
    return key;
  });

  Future<bool> hasSavedScrollback() => _files.hasScrollback();

  void dismissStrip() => ref.read(restoreStripProvider.notifier).dismiss();

  /// D7–D16. Call before anything may open a tab: from this call on, an
  /// activation waits for the restore (D16) — [load] may still be reading
  /// the file, or waiting for the first layout (so panes open at the real
  /// area grid, D17).
  Future<void> restoreAtStartup(FutureOr<RestoreLoad> load) async {
    if (_restoring || _frozen) return;
    _restoring = true;
    _debounce?.cancel(); // I7: never a partial layout mid-restore
    DateTime? newest;
    final planned = _plan(load, (at) {
      if (newest == null || at.isAfter(newest!)) newest = at;
    });
    try {
      final outcome = await ref
          .read(terminalTabsProvider.notifier)
          .restore(planned);
      final plan = await planned;
      if (!ref.mounted) return;
      _keys.addAll(outcome.keyBySession);
      _filed.addAll(outcome.keyBySession.values);
      if (plan == null) {
        if (!_frozen) await _files.removeOrphans(const {});
        return;
      }
      final snapshot = plan.snapshot;
      ref
          .read(sidebarWorkspacesProvider.notifier)
          .adopt(
            snapshot.workspaces,
            outcome.tabIdByKey,
            selectedTabId: ref.read(terminalTabsProvider).selectedId,
          );
      // D15. Not once Quit froze the files: the panes are going away and
      // the saved layout still names them.
      if (!_frozen) {
        await _files.removeOrphans(outcome.keyBySession.values.toSet());
      }
      if (!ref.mounted) return;
      // D12: an unclean end, and something to show for it.
      if (!snapshot.cleanExit && outcome.tabsRestored > 0) {
        ref
            .read(restoreStripProvider.notifier)
            .show(
              RestoreStripState(tabs: outcome.tabsRestored, contentsAt: newest),
            );
      }
    } on Object catch (error) {
      debugPrint('restore: startup failed (${error.runtimeType})');
    } finally {
      _restoring = false;
      // D12: the first write of this run marks it unclean.
      _schedule();
    }
  }

  /// The plan for [load]: per pane key, its saved text — sanitized here
  /// (D6, whatever [RestoreFiles] did) — ending its line, then the divider
  /// (D8, D23). Null when there is nothing to restore. Never throws.
  Future<RestorePlan?> _plan(
    FutureOr<RestoreLoad> load,
    void Function(DateTime at) savedAt,
  ) async {
    try {
      final snapshot = (await load).snapshot;
      if (snapshot == null) return null;
      final text = <String, String>{};
      if (scrollbackEnabled) {
        final l10n = ref.read(appL10nProvider);
        final now = ref.read(clockProvider)();
        for (final key in snapshot.paneKeys) {
          final raw = await _files.readScrollback(key);
          if (raw == null) continue;
          var saved = sanitizeRestored(raw);
          if (saved.isEmpty) continue;
          if (!saved.endsWith('\n')) saved += '\r\n';
          final at = await _files.scrollbackSavedAt(key) ?? snapshot.savedAt;
          savedAt(at);
          final time = formatRestoreTime(
            at,
            now,
            localeName: l10n.localeName,
            yesterday: l10n.restoreTimeYesterday,
          );
          text[key] =
              saved + restoreDivider(l10n.terminalRestoredDivider(time));
        }
      }
      return RestorePlan(snapshot: snapshot, textByKey: text);
    } on Object catch (error) {
      debugPrint('restore: saved state unreadable (${error.runtimeType})');
      return null;
    }
  }

  /// Quit and OS power-off (clean, D12, D18), window hidden (not clean).
  /// A clean flush is the last write of this run: persistence stops (the
  /// sessions closing after it must not undo it). During a restore
  /// nothing is written — the files on disk still hold everything.
  Future<void> flushAll({required bool clean}) async {
    if (_frozen) return;
    _debounce?.cancel();
    if (clean) {
      _frozen = true;
      _period?.cancel();
    }
    if (_restoring || !ref.mounted) return;
    await _writeLayout(cleanExit: clean, force: true);
    await _saveDirty();
  }

  /// D13: off deletes every saved text now and stops saving it; the
  /// layout is still saved.
  Future<void> setScrollbackEnabled(bool enabled) async {
    await _settings.setBool(SettingKeys.terminalRestoreScrollback, enabled);
    if (!enabled) await clearScrollback();
  }

  Future<void> clearScrollback() async {
    _dirty.clear();
    await _files.deleteAllScrollback();
  }

  bool get _paused => _frozen || _restoring || !ref.mounted;

  void _schedule() {
    if (_paused) return;
    _debounce?.cancel();
    _debounce = Timer(layoutDebounce, () {
      if (!_paused) unawaited(_writeLayout(cleanExit: false));
    });
  }

  void _tick() {
    if (_paused) return;
    // §5: a layout that never reached the disk is retried.
    if (_written == null && !(_debounce?.isActive ?? false)) {
      unawaited(_writeLayout(cleanExit: false));
    }
    unawaited(_saveDirty());
  }

  Future<void> _writeLayout({
    required bool cleanExit,
    bool force = false,
  }) async {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    final next = captureSnapshot(
      tabs: tabs,
      sidebar: ref.read(sidebarWorkspacesProvider),
      keyOf: keyOf,
      now: ref.read(clockProvider)(),
      cleanExit: cleanExit,
    );
    final previous = _written;
    if (!force && previous != null && previous.sameLayoutAs(next)) return;
    // D15: panes that left the layout lose their files once it is written.
    final gone = _filed.difference(next.paneKeys);
    _filed.removeAll(gone);
    _doomed.addAll(gone);
    _keys.removeWhere(
      (id, _) =>
          tabs.tabOfSession(id) == null && !tabs.tabs.any((t) => t.id == id),
    );
    bool ok;
    try {
      ok = await _files.writeLayout(next);
    } on Object catch (error) {
      debugPrint('restore: layout not saved (${error.runtimeType})');
      ok = false;
    }
    if (!ok) {
      _written = null; // §5: retried at the next save
      return;
    }
    _written = next;
    final doomed = List.of(_doomed);
    _doomed.clear();
    for (final key in doomed) {
      await _files.deleteScrollback(key);
    }
  }

  Future<void> _saveDirty() async {
    if (!ref.mounted || _dirty.isEmpty) return;
    if (!scrollbackEnabled) {
      _dirty.clear();
      return;
    }
    final tabs = ref.read(terminalTabsProvider);
    final ids = List.of(_dirty);
    _dirty.clear();
    final batch = <String, String>{};
    final saved = <int>[];
    for (final id in ids) {
      final pane = tabs.tabOfSession(id)?.panes[id];
      if (pane == null || pane.exited) continue;
      final text = encodeScrollback(pane.terminal);
      if (text.isEmpty) continue;
      batch[keyOf(id)] = text;
      saved.add(id);
    }
    if (batch.isEmpty) return;
    bool ok;
    try {
      ok = await _files.writeScrollbacks(batch);
    } on Object catch (error) {
      debugPrint('restore: scrollback not saved (${error.runtimeType})');
      ok = false;
    }
    // §5: kept dirty, saved at the next tick (unless switched off since).
    if (!ok && scrollbackEnabled) _dirty.addAll(saved);
  }
}
