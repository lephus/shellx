import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import '../platform/settings_store.dart';
import '../terminal/local_sessions_provider.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import 'config_files.dart';
import 'config_paths.dart';
import 'config_problem.dart';
import 'config_state.dart';
import 'config_syntax.dart';
import 'config_theme.dart';
import 'config_watcher.dart';
import 'keybindings.dart';
import 'shellx_config.dart';

export 'config_state.dart';

/// M4: a load whose reads have not finished by then reports the root as
/// unreadable, keeps the previous configuration, and lets the next load run.
const Duration kConfigLoadTimeout = Duration(seconds: 10);

final configFsProvider = Provider<ConfigFs>((ref) => const IoConfigFs());

/// Throws (ArgumentError) when the home directory is empty or relative;
/// the controller then keeps the defaults and reports a problem.
final configPathsProvider = Provider<ConfigPaths>(
  (ref) => configPathsFor(
    windows: Platform.isWindows,
    env: Platform.environment,
    home: ref.watch(homeDirectoryProvider),
  ),
);

final configPlatformProvider = Provider<TargetPlatform>(
  (ref) => defaultTargetPlatform,
);

final shellxConfigProvider = NotifierProvider<ConfigController, ConfigState>(
  ConfigController.new,
);

final class _Read {
  _Read({
    required this.problems,
    required this.files,
    this.config,
    this.theme,
    this.bindings,
    this.ghosttyUsed = false,
  });

  final ShellxConfig? config;
  final ResolvedTheme? theme;
  final KeyBindings? bindings;
  final List<ConfigProblem> problems;
  final List<String> files;
  final bool ghosttyUsed;

  /// D8: the ShellX file could not be read, or loading failed.
  bool get keepPrevious => config == null;
}

/// A9: the one owner of the configuration. Never loads on its own: startup
/// calls [load] (tests that don't, get the defaults and never touch the
/// real file system). Logs carry error types only, never file contents.
///
/// Rebuilding the provider (an invalidate, or a dependency it reads
/// changing) disposes the watcher and resets to the defaults: whoever does
/// that calls [load] and [startWatching] again (main.dart does it once).
///
/// A file made readable again by `chmod` keeps its size and modification
/// time, so the watcher does not see it: the user reloads (⌘⇧,).
class ConfigController extends Notifier<ConfigState> {
  ConfigWatcher? _watcher;
  Future<ConfigState>? _queue;

  /// The last published state: what [load] returns once the provider is
  /// disposed (Riverpod 3 throws on `state` then).
  late ConfigState _last;

  /// [ackGhosttyNotice] ran in this process (its write may be in flight).
  bool _noticeAcked = false;

  /// The label table this container last published (null: none yet).
  KeyBindings? _ownBindings;

  @override
  ConfigState build() {
    // A rebuilt provider starts from the defaults, not the old table.
    labelBindings = null;
    ref.onDispose(() {
      _watcher?.stop();
      _watcher = null;
      // Only this container's table: another container may own it now.
      if (identical(labelBindings, _ownBindings)) labelBindings = null;
    });
    return _last = ConfigState.initial(ref.read(configPlatformProvider));
  }

  void _publish(ConfigState next) {
    // Before the state, so a widget rebuilt by it reads the new labels.
    labelBindings = _ownBindings = next.bindings;
    // Before the listeners run: one that writes back (the window's Ghostty
    // acknowledgement, the font probe) builds on this state, not the last.
    _last = next;
    state = next;
  }

  /// Reads every file and publishes the result. Never throws (D10); loads
  /// run one after another, in call order, each bounded by
  /// [kConfigLoadTimeout].
  ///
  /// [ownWrite]: the app itself just saved a file; the watcher takes the
  /// new stamps as seen, so that save loads once, not twice.
  Future<ConfigState> load({bool manual = false, bool ownWrite = false}) {
    if (!ref.mounted) return Future.value(_last);
    final previous = _queue ?? Future<ConfigState>.value(_last);
    // _load never throws; the catch only keeps the chain alive if it did.
    final next = previous
        .catchError((Object _) => _last)
        .then((_) => _load(manual, ownWrite));
    _queue = next;
    return next;
  }

  /// `shellx config check` (D39): the problems of the files as they are
  /// now, without applying anything.
  Future<List<ConfigProblem>> check() async {
    try {
      return (await _read().timeout(kConfigLoadTimeout)).problems;
    } on TimeoutException {
      debugPrint('ShellX: config check timed out');
      return [_rootProblem(ConfigProblemCode.unreadable)];
    } catch (error) {
      debugPrint('ShellX: config check failed: ${error.runtimeType}');
      return [_rootProblem(ConfigProblemCode.internal)];
    }
  }

  /// D9: from now on, a saved file reloads by itself.
  void startWatching({Duration interval = const Duration(seconds: 1)}) {
    if (!ref.mounted) return;
    _watcher ??= ConfigWatcher(
      fs: ref.read(configFsProvider),
      interval: interval,
      onChange: () => unawaited(load()),
    );
    unawaited(_watcher!.watch(_last.files));
  }

  /// Problems only the UI can find (the font probe, D11), for [generation].
  /// Replaces earlier runtime problems with the same [codes]; the load's
  /// problems and [ConfigState.lastLoad] are untouched (I3). An identical
  /// report publishes nothing.
  void reportRuntimeProblems(
    int generation,
    Set<ConfigProblemCode> codes,
    List<ConfigProblem> problems,
  ) {
    if (!ref.mounted || generation != _last.generation) return;
    final next = [
      ..._last.runtimeProblems.where((p) => !codes.contains(p.code)),
      ...problems,
    ];
    if (listEquals(next, _last.runtimeProblems)) return;
    _publish(_last.copyWith(runtimeProblems: List.unmodifiable(next)));
  }

  /// D4: the UI showed the Ghostty notice; it is never due again.
  void ackGhosttyNotice() {
    if (!ref.mounted || !_last.ghosttyNoticePending) return;
    _noticeAcked = true;
    _publish(_last.copyWith(ghosttyNoticePending: false));
    try {
      unawaited(
        ref
            .read(settingsStoreProvider)
            .setBool(SettingKeys.configGhosttyNoticeShown, true)
            .catchError(
              (Object e) => debugPrint(
                'ShellX: ghostty notice flag not saved: ${e.runtimeType}',
              ),
            ),
      );
    } catch (error) {
      debugPrint('ShellX: ghostty notice flag not saved: ${error.runtimeType}');
    }
  }

  /// The notice was shown in this or an earlier launch. Unknown settings
  /// (no desktop services, as in tests with only the config overrides)
  /// count as shown: never nag on a guess.
  bool _ghosttyNoticeShown() {
    if (_noticeAcked) return true;
    try {
      return ref
          .read(settingsStoreProvider)
          .getBool(SettingKeys.configGhosttyNoticeShown, defaultValue: false);
    } catch (_) {
      return true;
    }
  }

  ConfigProblem _rootProblem(ConfigProblemCode code) {
    var file = '';
    try {
      file = ref.read(configPathsProvider).shellx;
    } catch (_) {
      // No usable home directory: the problem names no file.
    }
    return ConfigProblem(
      file: file,
      line: 0,
      severity: ConfigSeverity.error,
      code: code,
    );
  }

  static bool _same(List<ConfigProblem> a, List<ConfigProblem> b) =>
      setEquals(a.toSet(), b.toSet());

  Future<ConfigState> _load(bool manual, bool ownWrite) async {
    if (!ref.mounted) return _last;
    _Read read;
    try {
      read = await _read().timeout(kConfigLoadTimeout);
    } on TimeoutException {
      debugPrint('ShellX: config load timed out');
      read = _Read(
        problems: [_rootProblem(ConfigProblemCode.unreadable)],
        files: const [],
      );
    } catch (error) {
      debugPrint('ShellX: config load failed: ${error.runtimeType}');
      read = _Read(
        problems: [_rootProblem(ConfigProblemCode.internal)],
        files: const [],
      );
    }
    if (!ref.mounted) return _last;
    try {
      _publish(_next(read, manual));
    } catch (error) {
      debugPrint('ShellX: config publish failed: ${error.runtimeType}');
      try {
        if (ref.mounted) {
          _publish(
            _next(
              _Read(
                problems: [_rootProblem(ConfigProblemCode.internal)],
                files: const [],
              ),
              manual,
            ),
          );
        }
      } catch (_) {
        // Nothing more to do: the previous configuration stays.
      }
      return _last;
    }
    final watcher = _watcher;
    if (watcher != null) {
      unawaited(watcher.watch(_last.files, restamp: ownWrite));
    }
    return _last;
  }

  ConfigState _next(_Read read, bool manual) {
    final previous = _last;
    final pending =
        previous.ghosttyNoticePending ||
        (read.ghosttyUsed && !_ghosttyNoticeShown());
    final loadProblems = List<ConfigProblem>.unmodifiable(read.problems);
    // A new configuration drops the old one's runtime problems (the probe
    // runs again for it); a kept one keeps them.
    final runtime = read.keepPrevious
        ? previous.runtimeProblems
        : const <ConfigProblem>[];
    final load = ConfigLoad(
      manual: manual,
      problemsChanged: !_same([...loadProblems, ...runtime], previous.problems),
    );
    return read.keepPrevious
        ? previous.copyWith(
            loadProblems: loadProblems,
            generation: previous.generation + 1,
            files: read.files.isEmpty ? previous.files : read.files,
            ghosttyNoticePending: pending,
            lastLoad: load,
          )
        : ConfigState(
            config: read.config!,
            theme: read.theme!,
            bindings: read.bindings!,
            loadProblems: loadProblems,
            generation: previous.generation + 1,
            files: List.unmodifiable(read.files),
            ghosttyUsed: read.ghosttyUsed,
            ghosttyNoticePending: pending,
            lastLoad: load,
          );
  }

  Future<_Read> _read() async {
    final fs = ref.read(configFsProvider);
    final platform = ref.read(configPlatformProvider);
    final ConfigPaths paths;
    try {
      paths = ref.read(configPathsProvider);
    } catch (error) {
      // An empty or relative home (Task 2): no paths, keep the defaults.
      final cause = error is ProviderException ? error.exception : error;
      debugPrint('ShellX: config paths unavailable: ${cause.runtimeType}');
      return _Read(
        problems: [_rootProblem(ConfigProblemCode.internal)],
        files: const [],
      );
    }
    // Paths name the same file regardless of case on macOS and Windows.
    final caseInsensitive = paths.windows || platform == TargetPlatform.macOS;
    final problems = <ConfigProblem>[];
    final files = <String>[];
    final shellx = await loadConfigChain(
      paths.shellx,
      fs: fs,
      home: paths.home,
      windows: paths.windows,
      problems: problems,
      caseInsensitive: caseInsensitive,
    );
    files.addAll(shellx.files);
    if (!shellx.readable) {
      return _Read(problems: problems, files: [...files, ...paths.ghostty]);
    }
    // D4: in ConfigPaths.ghostty order, a later file over an earlier one;
    // none read when `ghostty-config = false` (turning it back on is an
    // edit of the ShellX file, which is watched).
    final ghostty = <ConfigEntry>[];
    if (ghosttyEnabled(shellx.entries)) {
      for (final path in paths.ghostty) {
        final chain = await loadConfigChain(
          path,
          fs: fs,
          home: paths.home,
          windows: paths.windows,
          problems: problems,
          quiet: true,
          keep: kGhosttyKeys.contains,
          caseInsensitive: caseInsensitive,
        );
        ghostty.addAll(chain.entries);
        files.addAll(chain.files);
      }
    }
    final config = buildShellxConfig(
      ghostty: ghostty,
      shellx: shellx.entries,
      problems: problems,
      macos: platform == TargetPlatform.macOS,
      home: paths.home,
      windows: paths.windows,
    );
    final theme = await resolveTheme(config, paths, fs: fs, problems: problems);
    files.addAll(theme.files);
    final bindings = resolveKeyBindings(
      platform: platform,
      entries: config.keybinds,
      commandNames: {for (final c in config.commands) c.name},
      optionAsAlt: config.optionAsAlt,
      problems: problems,
    );
    return _Read(
      config: config,
      theme: theme.theme,
      bindings: bindings,
      problems: problems,
      files: files,
      ghosttyUsed: ghostty.isNotEmpty,
    );
  }
}
