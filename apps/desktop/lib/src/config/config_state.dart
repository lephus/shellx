import 'package:flutter/foundation.dart';

import 'config_problem.dart';
import 'config_theme.dart';
import 'keybindings.dart';
import 'shellx_config.dart';

/// One load, as the UI sees it (toasts, D36). Only a load sets it; runtime
/// problems (the font probe) never replace it (controller ruling I3).
@immutable
final class ConfigLoad {
  const ConfigLoad({required this.manual, required this.problemsChanged});

  /// The user asked for it (⌘⇧, / the palette / `shellx config reload`).
  final bool manual;

  /// The shown problem set differs from the one before (D36: toast only
  /// then).
  final bool problemsChanged;
}

@immutable
final class ConfigState {
  const ConfigState({
    required this.config,
    required this.theme,
    required this.bindings,
    required this.loadProblems,
    required this.generation,
    required this.files,
    required this.ghosttyUsed,
    this.runtimeProblems = const [],
    this.ghosttyNoticePending = false,
    this.lastLoad,
  });

  factory ConfigState.initial(TargetPlatform platform) => ConfigState(
    config: ShellxConfig.defaults,
    theme: ResolvedTheme.defaults,
    bindings: KeyBindings.defaults(platform),
    loadProblems: const [],
    generation: 0,
    files: const [],
    ghosttyUsed: false,
  );

  final ShellxConfig config;
  final ResolvedTheme theme;
  final KeyBindings bindings;

  /// What the last load found in the files.
  final List<ConfigProblem> loadProblems;

  /// What the UI found for this [generation] (the font probe, D11).
  final List<ConfigProblem> runtimeProblems;

  /// 0 before the first load; +1 per load.
  final int generation;

  /// Every path the last successful read looked at (the watcher's list).
  final List<String> files;
  final bool ghosttyUsed;

  /// D4: "Đang dùng font và màu từ cấu hình Ghostty" is due. Set by the
  /// first load that used a Ghostty file (problems or not); stays set
  /// through later loads and runtime reports until the UI shows it and
  /// calls `ConfigController.ackGhosttyNotice()`.
  final bool ghosttyNoticePending;
  final ConfigLoad? lastLoad;

  /// Everything shown: the load's problems, then the runtime ones.
  List<ConfigProblem> get problems => runtimeProblems.isEmpty
      ? loadProblems
      : List.unmodifiable([...loadProblems, ...runtimeProblems]);

  int get errorCount =>
      problems.where((p) => p.severity == ConfigSeverity.error).length;

  /// Errors and warnings: what the toast and the tray count (D36, D45).
  int get visibleProblemCount =>
      problems.where((p) => p.severity != ConfigSeverity.info).length;

  ConfigState copyWith({
    List<ConfigProblem>? loadProblems,
    List<ConfigProblem>? runtimeProblems,
    int? generation,
    List<String>? files,
    bool? ghosttyNoticePending,
    ConfigLoad? lastLoad,
  }) => ConfigState(
    config: config,
    theme: theme,
    bindings: bindings,
    loadProblems: loadProblems ?? this.loadProblems,
    runtimeProblems: runtimeProblems ?? this.runtimeProblems,
    generation: generation ?? this.generation,
    files: files ?? this.files,
    ghosttyUsed: ghosttyUsed,
    ghosttyNoticePending: ghosttyNoticePending ?? this.ghosttyNoticePending,
    lastLoad: lastLoad ?? this.lastLoad,
  );
}
