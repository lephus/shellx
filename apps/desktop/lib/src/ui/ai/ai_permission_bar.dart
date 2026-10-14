import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_labels.dart';
import 'ai_scope.dart';

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const _numpad = [
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// D10: the permission bar's keys, offered by the composer before its own
/// (the bar never takes the focus). On key-down:
/// - 1–9 pick the options in the agent's order — not while the composer
///   has text (they are typing) and never with ⌘/Ctrl/Alt (⌘1 picks a tab);
/// - Esc picks the first `reject_*` option, or answers `cancelled` when
///   there is none.
/// Nothing ever picks an `allow_*` option by itself.
bool aiPermissionKeys(
  AiRuntime runtime,
  KeyEvent event, {
  required bool hasText,
}) {
  final pending = runtime.state.currentPermission;
  if (pending == null || event is! KeyDownEvent) return false;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.escape) {
    final reject = pending.request.options
        .where((o) => o.kind.isReject)
        .firstOrNull;
    runtime.answerPermission(pending.id, reject?.optionId);
    return true;
  }
  if (hasText) return false;
  final hw = HardwareKeyboard.instance;
  if (hw.isMetaPressed || hw.isControlPressed || hw.isAltPressed) return false;
  var n = _digits.indexOf(key);
  if (n < 0) n = _numpad.indexOf(key);
  final options = pending.request.options;
  if (n < 0 || n >= options.length) return false;
  runtime.answerPermission(pending.id, options[n].optionId);
  return true;
}

/// D10, spec §4.3: the request being asked (one at a time; the next waits
/// its turn). The first line is a live region, read once; each option is a
/// button with its key; the first reject also shows Esc; the agent's own
/// words for an "always" option stay visible under them.
class AiPermissionBar extends StatelessWidget {
  const AiPermissionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: scope.frames,
      builder: (context, _) {
        final pending = scope.state.currentPermission;
        if (pending == null) return const SizedBox.shrink();
        final options = pending.request.options;
        final firstReject = options.indexWhere((o) => o.kind.isReject);
        final always = options
            .where(
              (o) =>
                  o.kind == PermissionKind.allowAlways ||
                  o.kind == PermissionKind.rejectAlways,
            )
            .firstOrNull;
        return ExcludeFocus(
          child: Container(
            key: const Key('ai.permission'),
            margin: const EdgeInsets.fromLTRB(
              ShellxSpace.s16,
              ShellxSpace.s4,
              ShellxSpace.s16,
              0,
            ),
            padding: const EdgeInsets.all(ShellxSpace.s12),
            decoration: BoxDecoration(
              color: ShellxDesktopColors.warnBg,
              borderRadius: BorderRadius.circular(ShellxRadius.r8),
              border: Border.all(color: ShellxDesktopColors.warnBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.aiPermTitle(scope.state.agentName, pending.title),
                    style: ShellxText.bodyStrong.copyWith(
                      color: ShellxDesktopColors.textTitle,
                    ),
                  ),
                ),
                const SizedBox(height: ShellxSpace.s8),
                Wrap(
                  spacing: ShellxSpace.s8,
                  runSpacing: ShellxSpace.s6,
                  children: [
                    for (final (i, o) in options.indexed)
                      _OptionButton(
                        key: ValueKey('ai.permission.${i + 1}'),
                        number: i + 1,
                        label: aiPermissionLabel(l10n, o),
                        tooltip: o.name,
                        esc: i == firstReject,
                        reject: o.kind.isReject,
                        onPressed: () => scope.runtime.answerPermission(
                          pending.id,
                          o.optionId,
                        ),
                      ),
                  ],
                ),
                if (always != null) ...[
                  const SizedBox(height: ShellxSpace.s6),
                  Text(
                    l10n.aiPermAlwaysNote(
                      aiPermissionLabel(l10n, always),
                      scope.state.agentName,
                      always.name,
                    ),
                    style: ShellxText.small.copyWith(
                      color: ShellxDesktopColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    super.key,
    required this.number,
    required this.label,
    required this.tooltip,
    required this.esc,
    required this.reject,
    required this.onPressed,
  });

  final int number;
  final String label;
  final String tooltip;
  final bool esc;
  final bool reject;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    Widget kbd(String k) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: ShellxDesktopColors.border),
        borderRadius: BorderRadius.circular(ShellxRadius.r4),
      ),
      child: Text(k, style: ShellxText.caption),
    );
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            kbd('$number'),
            const SizedBox(width: ShellxSpace.s6),
            Text(
              label,
              style: TextStyle(
                color: reject
                    ? ShellxDesktopColors.err
                    : ShellxDesktopColors.textPrimary,
              ),
            ),
            if (esc) ...[const SizedBox(width: ShellxSpace.s6), kbd('Esc')],
          ],
        ),
      ),
    );
  }
}
