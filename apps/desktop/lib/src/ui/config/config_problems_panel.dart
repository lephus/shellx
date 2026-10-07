import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/config_problem.dart';
import '../terminal/terminal_overlays.dart';
import '../theme/shellx_desktop_theme.dart';
import 'action_labels.dart';

/// `~` for the home folder, only at a path separator boundary
/// (`/home/me` is not the prefix of `/home/meow`).
String homeRelative(String path, String home) {
  if (home.isEmpty || !path.startsWith(home)) return path;
  final rest = path.substring(home.length);
  if (rest.isEmpty) return '~';
  final boundary = rest.startsWith('/') || rest.startsWith(r'\');
  return boundary || home.endsWith('/') || home.endsWith(r'\')
      ? '~$rest'
      : path;
}

/// Keeps the start and the end of a long path, the middle becomes "…"
/// (UI-A9 §3.2: cut in the middle).
String middleEllipsis(String text, {int max = 72}) {
  if (text.length <= max) return text;
  final head = (max - 1) ~/ 2;
  final tail = max - 1 - head;
  return '${text.substring(0, head)}…${text.substring(text.length - tail)}';
}

int _rank(ConfigSeverity s) => switch (s) {
  ConfigSeverity.error => 0,
  ConfigSeverity.warning => 1,
  ConfigSeverity.info => 2,
};

/// UI-A9 §3.2. Lives in the workspace overlay slot; reads the problems
/// live, so a reload updates it in place.
class ConfigProblemsPanel extends ConsumerStatefulWidget {
  const ConfigProblemsPanel({
    super.key,
    required this.onClose,
    required this.onOpenFile,
    required this.onReload,
  });

  final VoidCallback onClose;
  final VoidCallback onOpenFile;
  final VoidCallback onReload;

  @override
  ConsumerState<ConfigProblemsPanel> createState() =>
      _ConfigProblemsPanelState();
}

class _ConfigProblemsPanelState extends ConsumerState<ConfigProblemsPanel> {
  final _openFocus = FocusNode(debugLabel: 'problems open file');
  final _listFocus = FocusNode(debugLabel: 'problems list');
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Opening puts the keyboard on the primary button.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _openFocus.dispose();
    _listFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The files being read, `~` for the home; none when the home is unusable.
  String _filesLine(ConfigState state) {
    try {
      final paths = ref.read(configPathsProvider);
      String home(String path) => homeRelative(path, paths.home);
      final ghostty = [
        for (final f in paths.ghostty)
          if (state.ghosttyUsed && state.files.contains(f)) home(f),
      ];
      return middleEllipsis(
        [
          home(paths.shellx),
          if (ghostty.isNotEmpty) 'Ghostty: ${ghostty.join(', ')}',
        ].join(' · '),
      );
    } catch (_) {
      return '';
    }
  }

  static const _lineStep = 40.0;

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final p = _scroll.position;
    final page = p.viewportDimension * 0.9;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => _lineStep,
      LogicalKeyboardKey.arrowUp => -_lineStep,
      LogicalKeyboardKey.pageDown => page,
      LogicalKeyboardKey.pageUp => -page,
      LogicalKeyboardKey.home => -p.pixels,
      LogicalKeyboardKey.end => p.maxScrollExtent - p.pixels,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;
    _scroll.jumpTo((p.pixels + delta).clamp(0.0, p.maxScrollExtent));
    return KeyEventResult.handled;
  }

  /// The list is a focus stop (arrows and page keys scroll it) with a
  /// visible ring while it has the keyboard.
  Widget _listBox(List<ConfigProblem> problems) => Focus(
    focusNode: _listFocus,
    onKeyEvent: _onListKey,
    child: ListenableBuilder(
      listenable: _listFocus,
      builder: (context, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border:
              _listFocus.hasFocus &&
                  FocusManager.instance.highlightMode ==
                      FocusHighlightMode.traditional
              ? Border.all(
                  color: ShellxDesktopColors.accent,
                  width: ShellxSizes.focusRing,
                )
              : null,
        ),
        child: child,
      ),
      child: ListView(
        controller: _scroll,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [for (final p in problems) _ProblemRow(problem: p)],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shellxConfigProvider);
    // Errors, warnings, notes; then file and line; ties by code, then by
    // the order found (a stable sort).
    final indexed = [...state.problems.indexed];
    indexed.sort((a, b) {
      final x = a.$2, y = b.$2;
      final s = _rank(x.severity).compareTo(_rank(y.severity));
      if (s != 0) return s;
      final f = x.file.compareTo(y.file);
      if (f != 0) return f;
      final l = x.line.compareTo(y.line);
      if (l != 0) return l;
      final c = x.code.index.compareTo(y.code.index);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    final problems = [for (final e in indexed) e.$2];
    final files = _filesLine(state);
    final size = MediaQuery.sizeOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: FocusScope(
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: l10n.configProblemsTitle,
          child: Container(
            width: math.min(ShellxSizes.problemsWidth, size.width - 48),
            constraints: BoxConstraints(
              maxHeight: math.min(
                ShellxSizes.problemsMaxHeight,
                size.height - 96,
              ),
            ),
            decoration: BoxDecoration(
              color: ShellxDesktopColors.surface,
              borderRadius: BorderRadius.circular(ShellxRadius.r8),
              border: Border.all(color: ShellxDesktopColors.border),
              boxShadow: ShellxShadows.e1,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                l10n.configProblemsTitle,
                                style: ShellxText.bodyStrong.copyWith(
                                  color: ShellxDesktopColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(3),
                            child: ShellxIconButton(
                              icon: Icons.close,
                              semanticLabel: l10n.toastDismiss,
                              tooltip: TextSpan(text: l10n.toastDismiss),
                              onPressed: widget.onClose,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (files.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          files,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.caption.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ),
                    // A reload while open is read out in place (UI-A9 §3.2).
                    Semantics(
                      liveRegion: true,
                      container: true,
                      label: state.visibleProblemCount == 0
                          ? l10n.configProblemsNone
                          : l10n.configProblemsToast(state.visibleProblemCount),
                      child: const SizedBox(width: 1, height: 1),
                    ),
                    const Divider(height: 1, color: ShellxDesktopColors.line),
                    Flexible(
                      child: problems.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                l10n.configProblemsNone,
                                textAlign: TextAlign.center,
                                style: ShellxText.body.copyWith(
                                  color: ShellxDesktopColors.textSecondary,
                                ),
                              ),
                            )
                          : FocusTraversalOrder(
                              order: const NumericFocusOrder(0),
                              child: _listBox(problems),
                            ),
                    ),
                    const Divider(height: 1, color: ShellxDesktopColors.line),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: OutlinedButton(
                              onPressed: widget.onReload,
                              child: Text(l10n.configReload),
                            ),
                          ),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(2),
                            child: ShellxPrimaryButton(
                              label: l10n.configOpenFile,
                              focusNode: _openFocus,
                              onPressed: widget.onOpenFile,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProblemRow extends StatelessWidget {
  const _ProblemRow({required this.problem});
  final ConfigProblem problem;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, color) = switch (problem.severity) {
      ConfigSeverity.error => (Icons.error_outline, ShellxDesktopColors.err),
      ConfigSeverity.warning => (Icons.warning_amber, ShellxDesktopColors.warn),
      ConfigSeverity.info => (
        Icons.info_outline,
        ShellxDesktopColors.textSecondary,
      ),
    };
    final severity = severityText(l10n, problem.severity);
    final where = problemLocation(l10n, problem);
    final message = problemText(l10n, problem);
    return Semantics(
      label: [severity, if (where.isNotEmpty) where, message].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      severity,
                      style: ShellxText.small.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (where.isNotEmpty)
                    Text(
                      where,
                      style: ShellxText.small.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  Text(
                    message,
                    style: ShellxText.body.copyWith(
                      color: ShellxDesktopColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
