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
    super.dispose();
  }

  /// The files being read, `~` for the home; none when the home is unusable.
  String _filesLine(ConfigState state) {
    try {
      final paths = ref.read(configPathsProvider);
      String home(String path) =>
          paths.home.isNotEmpty && path.startsWith(paths.home)
          ? '~${path.substring(paths.home.length)}'
          : path;
      final ghostty = [
        for (final f in paths.ghostty)
          if (state.ghosttyUsed && state.files.contains(f)) home(f),
      ];
      return [
        home(paths.shellx),
        if (ghostty.isNotEmpty) 'Ghostty: ${ghostty.join(', ')}',
      ].join(' · ');
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shellxConfigProvider);
    final problems = [...state.problems]
      ..sort((a, b) {
        final s = _rank(a.severity).compareTo(_rank(b.severity));
        if (s != 0) return s;
        final f = a.file.compareTo(b.file);
        return f != 0 ? f : a.line.compareTo(b.line);
      });
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
                      label: state.visibleProblemCount == 0
                          ? l10n.configProblemsNone
                          : l10n.configProblemsToast(state.visibleProblemCount),
                      child: const SizedBox(width: 0, height: 0),
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
                          : ListView(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              children: [
                                for (final p in problems)
                                  _ProblemRow(problem: p),
                              ],
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
                  Text(
                    severity,
                    style: ShellxText.small.copyWith(color: color),
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
