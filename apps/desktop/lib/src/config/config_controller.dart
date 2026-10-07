import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import '../agent/desktop_services.dart';
import '../platform/settings_store.dart';
import '../terminal/local_sessions_provider.dart';
import 'config_files.dart';
import 'config_paths.dart';
import 'config_problem.dart';
import 'config_syntax.dart';
import 'config_theme.dart';
import 'config_watcher.dart';
import 'keybindings.dart';
import 'shellx_config.dart';

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

/// What the last load means for the UI (toasts, D36).
@immutable
final class ConfigLoad {
  const ConfigLoad({
    required this.manual,
    required this.problemsChanged,
    required this.firstGhostty,
  });

  /// The user asked for it (⌘⇧, / the palette / `shellx config reload`).
  final bool manual;

  /// The problem set differs from the one before (D36: toast only then).
  final bool problemsChanged;

  /// D4: the first load ever that used a Ghostty file — the one-time
  /// notice. Independent of problems: a first load with problems still
  /// carries it (preflight D8).
  final bool firstGhostty;
}

@immutable
final class ConfigState {
  const ConfigState({
    required this.config,
    required this.theme,
    required this.bindings,
    required this.problems,
    required this.generation,
    required this.files,
    required this.ghosttyUsed,
    this.lastLoad,
  });

  factory ConfigState.initial(TargetPlatform platform) => ConfigState(
    config: ShellxConfig.defaults,
    theme: ResolvedTheme.defaults,
    bindings: KeyBindings.defaults(platform),
    problems: const [],
    generation: 0,
    files: const [],
    ghosttyUsed: false,
  );

  final ShellxConfig config;
  final ResolvedTheme theme;
  final KeyBindings bindings;
  final List<ConfigProblem> problems;

  /// 0 before the first load; +1 per load.
  final int generation;

  /// Every path the last successful read looked at (the watcher's list).
  final List<String> files;
  final bool ghosttyUsed;
  final ConfigLoad? lastLoad;

  int get errorCount =>
      problems.where((p) => p.severity == ConfigSeverity.error).length;

  /// Errors and warnings: what the toast and the tray count (D36, D45).
  int get visibleProblemCount =>
      problems.where((p) => p.severity != ConfigSeverity.info).length;

  ConfigState copyWith({
    List<ConfigProblem>? problems,
    int? generation,
    List<String>? files,
    ConfigLoad? lastLoad,
  }) => ConfigState(
    config: config,
    theme: theme,
    bindings: bindings,
    problems: problems ?? this.problems,
    generation: generation ?? this.generation,
    files: files ?? this.files,
    ghosttyUsed: ghosttyUsed,
    lastLoad: lastLoad ?? this.lastLoad,
  );
}

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
class ConfigController extends Notifier<ConfigState> {
  ConfigWatcher? _watcher;
  Future<ConfigState>? _queue;

  @override
  ConfigState build() {
    ref.onDispose(() {
      _watcher?.stop();
      _watcher = null;
      labelBindings = null;
    });
    return ConfigState.initial(ref.read(configPlatformProvider));
  }

  /// Reads every file and publishes the result. Never throws (D10); loads
  /// run one after another, in call order.
  Future<ConfigState> load({bool manual = false}) {
    final previous = _queue ?? Future<ConfigState>.value(state);
    // _load never throws; the catch only keeps the chain alive if it did.
    final next = previous
        .catchError((Object _) => state)
        .then((_) => _load(manual));
    _queue = next;
    return next;
  }

  /// `shellx config check` (D39): the problems of the files as they are
  /// now, without applying anything.
  Future<List<ConfigProblem>> check() async {
    try {
      return (await _read()).problems;
    } catch (error) {
      debugPrint('ShellX: config check failed: ${error.runtimeType}');
      return [_internal()];
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
    unawaited(_watcher!.watch(state.files));
  }

  /// Problems only the UI can find (the font probe, D11), for [generation].
  /// Replaces earlier problems with the same [codes].
  void reportRuntimeProblems(
    int generation,
    Set<ConfigProblemCode> codes,
    List<ConfigProblem> problems,
  ) {
    if (!ref.mounted || generation != state.generation) return;
    final next = List<ConfigProblem>.unmodifiable([
      ...state.problems.where((p) => !codes.contains(p.code)),
      ...problems,
    ]);
    state = state.copyWith(
      problems: next,
      lastLoad: ConfigLoad(
        manual: false,
        problemsChanged: !_same(next, state.problems),
        firstGhostty: false,
      ),
    );
  }

  ConfigProblem _internal() {
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
      code: ConfigProblemCode.internal,
    );
  }

  static bool _same(List<ConfigProblem> a, List<ConfigProblem> b) =>
      setEquals(a.toSet(), b.toSet());

  Future<ConfigState> _load(bool manual) async {
    if (!ref.mounted) return state;
    _Read read;
    try {
      read = await _read();
    } catch (error) {
      debugPrint('ShellX: config load failed: ${error.runtimeType}');
      read = _Read(problems: [_internal()], files: const []);
    }
    if (!ref.mounted) return state;
    final firstGhostty = read.ghosttyUsed && _claimGhosttyNotice();
    final load = ConfigLoad(
      manual: manual,
      problemsChanged: !_same(read.problems, state.problems),
      firstGhostty: firstGhostty,
    );
    state = read.keepPrevious
        ? state.copyWith(
            problems: List.unmodifiable(read.problems),
            generation: state.generation + 1,
            files: read.files.isEmpty ? state.files : read.files,
            lastLoad: load,
          )
        : ConfigState(
            config: read.config!,
            theme: read.theme!,
            bindings: read.bindings!,
            problems: List.unmodifiable(read.problems),
            generation: state.generation + 1,
            files: List.unmodifiable(read.files),
            ghosttyUsed: read.ghosttyUsed,
            lastLoad: load,
          );
    labelBindings = state.bindings;
    final watcher = _watcher;
    if (watcher != null) unawaited(watcher.watch(state.files));
    return state;
  }

  /// D4: true once — the load that publishes the Ghostty notice sets the
  /// "shown" flag in the same step, so the flag is never set for a notice
  /// that was not published.
  bool _claimGhosttyNotice() {
    final settings = ref.read(desktopServicesProvider).settings;
    if (settings.getBool(
      SettingKeys.configGhosttyNoticeShown,
      defaultValue: false,
    )) {
      return false;
    }
    unawaited(
      settings
          .setBool(SettingKeys.configGhosttyNoticeShown, true)
          .catchError(
            (Object e) => debugPrint(
              'ShellX: ghostty notice flag not saved: ${e.runtimeType}',
            ),
          ),
    );
    return true;
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
      return _Read(problems: [_internal()], files: const []);
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
