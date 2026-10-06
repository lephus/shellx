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

/// Whether any saved terminal text is on disk (D13: "Xóa nội dung đã lưu"
/// is greyed out without). Read from the files at first use;
/// [RestorePersistence] refreshes it whenever it writes or deletes some.
final savedScrollbackProvider = NotifierProvider<SavedScrollback, bool>(
  SavedScrollback.new,
);

class SavedScrollback extends Notifier<bool> {
  @override
  bool build() {
    unawaited(refresh());
    return false;
  }

  /// Asks the files. [RestoreStore] runs its operations in call order, so
  /// the answer reflects every write or delete issued before this call.
  Future<void> refresh() async {
    bool has;
    try {
      has = await ref.read(restoreStoreProvider).hasScrollback();
    } on Object catch (error) {
      debugPrint('restore: saved text not checked (${error.runtimeType})');
      return;
    }
    if (ref.mounted) state = has;
  }
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

  /// A layout change is written at most this long after it happened, even
  /// while changes keep coming (a title that ticks every second).
  static const layoutMaxWait = Duration(seconds: 5);
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

  /// Started with the first change of a burst; never restarted (I1).
  Timer? _maxWait;
  Timer? _period;

  /// The scrollback save under way; [flushAll] waits for it.
  Future<void> _saving = Future.value();

  /// The last layout on disk; null before the first write and after a
  /// failed one (§5: the next save retries).
  RestoreSnapshot? _written;
  bool _started = false;
  bool _restoring = false;

  /// Set by `flushAll(clean: true)`: what Quit saved is final (D12); the
  /// shutdown that follows must not overwrite or delete it.
  bool _frozen = false;

  /// The layout write of the last [flushAll]; [resume] waits for it.
  Future<void> _flushWrite = Future.value();

  /// A [resume] waiting for [_flushWrite]; a new clean flush cancels it.
  bool _resuming = false;

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
      _cancelPending();
      _period?.cancel();
      // The listeners [start] made go with this build: a rebuild (the
      // notifier is reused) needs [start] again.
      _started = false;
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

  /// After `flushAll(clean: true)` the quit or power-off did not happen
  /// (the user cancelled it): saving goes on, and the next layout write
  /// marks the run unclean again (D12). Task 7 calls it.
  void resume() {
    if (!_frozen || _resuming || !ref.mounted) return;
    _resuming = true;
    // The clean layout may still be on its way to the disk: unfreeze once
    // it is there, so the unclean one is written after it, not skipped as
    // equal to it.
    unawaited(
      _flushWrite.catchError((Object _) {}).then((_) {
        if (!_resuming || !ref.mounted) return;
        _resuming = false;
        _frozen = false;
        _written = null; // the next write must happen even when equal
        if (_started) {
          _period?.cancel();
          _period = Timer.periodic(scrollbackPeriod, (_) => _tick());
        }
        _schedule();
      }),
    );
  }

  void dismissStrip() => ref.read(restoreStripProvider.notifier).dismiss();

  /// D7–D16. Call before anything may open a tab: from this call on, an
  /// activation waits for the restore (D16) — [load] may still be reading
  /// the file, or waiting for the first layout (so panes open at the real
  /// area grid, D17).
  Future<void> restoreAtStartup(FutureOr<RestoreLoad> load) async {
    if (_restoring || _frozen) return;
    _restoring = true;
    _cancelPending(); // I7: never a partial layout mid-restore
    final files = _files;
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
        if (!_frozen) await files.removeOrphans(const {});
        _savedChanged();
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
        await files.removeOrphans(outcome.keyBySession.values.toSet());
      }
      if (!ref.mounted) return;
      _savedChanged();
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
      final files = _files;
      final enabled = scrollbackEnabled;
      final l10n = ref.read(appL10nProvider);
      final now = ref.read(clockProvider)();
      final snapshot = (await load).snapshot;
      if (snapshot == null || !ref.mounted) return null;
      // D12: a crash while restoring must read as unclean next time. Same
      // layout, so nothing is lost; a Quit during the restore writes
      // nothing more ([flushAll]).
      if (snapshot.cleanExit && !_frozen) {
        try {
          await files.writeLayout(snapshot.copyWith(cleanExit: false));
        } on Object catch (error) {
          debugPrint('restore: marker not saved (${error.runtimeType})');
        }
      }
      final text = <String, String>{};
      if (enabled) {
        for (final key in snapshot.paneKeys) {
          final raw = await files.readScrollback(key);
          if (raw == null) continue;
          var saved = sanitizeRestored(raw);
          if (saved.isEmpty) continue;
          if (!saved.endsWith('\n')) saved += '\r\n';
          final at = await files.scrollbackSavedAt(key) ?? snapshot.savedAt;
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
  /// nothing is written — the files on disk still hold everything (the
  /// restore marked them unclean). Returns once any scrollback save that
  /// was already under way has finished too.
  Future<void> flushAll({required bool clean}) async {
    if (clean) _resuming = false; // quitting again: stay frozen
    if (_frozen) return;
    _cancelPending();
    if (clean) {
      _frozen = true;
      _period?.cancel();
    }
    if (_restoring || !ref.mounted) return;
    final write = _flushWrite = _writeLayout(cleanExit: clean, force: true);
    await write;
    await _saveDirty();
  }

  /// D13: off deletes every saved text now and stops saving it; the
  /// layout is still saved.
  /// Switched back on, every live pane is saved at the next tick, idle
  /// or not: what was dropped while off is not on disk (D13).
  Future<void> setScrollbackEnabled(bool enabled) async {
    final files = _files;
    await _settings.setBool(SettingKeys.terminalRestoreScrollback, enabled);
    if (!enabled) {
      _dirty.clear();
      await files.deleteAllScrollback();
      _savedChanged();
      return;
    }
    _markAllDirty();
  }

  /// UI-A5 §3: the live panes' text comes back at the next save.
  Future<void> clearScrollback() async {
    _dirty.clear();
    await _files.deleteAllScrollback();
    _savedChanged();
    _markAllDirty();
  }

  /// Every live pane is saved at the next tick, idle or not.
  void _markAllDirty() {
    if (!ref.mounted) return;
    for (final tab in ref.read(terminalTabsProvider).tabs) {
      for (final pane in tab.panes.values) {
        if (!pane.exited) _dirty.add(pane.id);
      }
    }
  }

  void _savedChanged() {
    if (ref.mounted) {
      unawaited(ref.read(savedScrollbackProvider.notifier).refresh());
    }
  }

  bool get _paused => !_started || _frozen || _restoring || !ref.mounted;

  void _cancelPending() {
    _debounce?.cancel();
    _maxWait?.cancel();
    _debounce = _maxWait = null;
  }

  void _schedule() {
    if (_paused) return;
    void write() {
      _cancelPending();
      if (!_paused) unawaited(_writeLayout(cleanExit: false));
    }

    _debounce?.cancel();
    _debounce = Timer(layoutDebounce, write);
    _maxWait ??= Timer(layoutMaxWait, write);
  }

  void _tick() {
    if (_paused) return;
    // §5: a layout that did not reach the disk is retried; an equal one
    // is skipped.
    unawaited(_writeLayout(cleanExit: false));
    unawaited(_saveDirty());
  }

  Future<void> _writeLayout({
    required bool cleanExit,
    bool force = false,
  }) async {
    if (!ref.mounted) return;
    final files = _files;
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
      ok = await files.writeLayout(next);
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
      await files.deleteScrollback(key);
    }
    if (doomed.isNotEmpty) _savedChanged();
  }

  /// One save at a time, in call order (MINOR 7: [flushAll] returns after
  /// the one under way).
  Future<void> _saveDirty() {
    final run = _saving.then((_) => _saveDirtyNow());
    _saving = run.catchError((Object _) {});
    return run;
  }

  Future<void> _saveDirtyNow() async {
    if (!ref.mounted || _dirty.isEmpty) return;
    final files = _files;
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
      ok = await files.writeScrollbacks(batch);
    } on Object catch (error) {
      debugPrint('restore: scrollback not saved (${error.runtimeType})');
      ok = false;
    }
    // §5: kept dirty, saved at the next tick (unless switched off since).
    if (!ok && ref.mounted && scrollbackEnabled) _dirty.addAll(saved);
    if (ok) _savedChanged();
  }
}
