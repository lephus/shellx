import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/agent_names.dart';
import '../../terminal/resume_offers.dart';
import '../theme/shellx_desktop_theme.dart';

/// A12 D13, UI §4.2: the strip over the top of a restored pane that offers
/// to continue the agent that was running there. It never takes the
/// keyboard from the terminal on mount; its buttons are reached by Tab like
/// any other (or by the screen reader), Esc on them dismisses it. Nothing is
/// typed until "Resume session" is pressed, once.
class ResumeBanner extends ConsumerStatefulWidget {
  const ResumeBanner({super.key, required this.pane, required this.offer});
  final int pane;
  final ResumeOffer offer;

  @override
  ConsumerState<ResumeBanner> createState() => _ResumeBannerState();
}

class _ResumeBannerState extends ConsumerState<ResumeBanner> {
  final _resumeFocus = FocusNode(debugLabel: 'resume session');
  final _dismissFocus = FocusNode(debugLabel: 'resume dismiss');

  @override
  void dispose() {
    _resumeFocus.dispose();
    _dismissFocus.dispose();
    super.dispose();
  }

  void _dismiss() =>
      ref.read(resumeOffersProvider.notifier).dismiss(widget.pane);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offer = widget.offer;
    final name = agentDisplayName(l10n, offer.kind);
    final text = l10n.resumeBannerText(name);
    // Built for the tooltip only: the id passed the strict pattern, or
    // there is no command and no banner.
    final command = resumeCommand(offer.kind, offer.session);
    if (command == null) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    final height = max(36.0, scaler.scale(18) + 16);
    final resume = TextButton(
      key: Key('resume.go.${widget.pane}'),
      focusNode: _resumeFocus,
      style: _buttonStyle(primary: true),
      onPressed: () =>
          ref.read(resumeOffersProvider.notifier).resume(widget.pane),
      child: Text(l10n.resumeBannerResume),
    );
    final dismiss = TextButton(
      key: Key('resume.dismiss.${widget.pane}'),
      focusNode: _dismissFocus,
      style: _buttonStyle(primary: false),
      onPressed: _dismiss,
      child: Text(l10n.resumeBannerDismiss),
    );
    final windows = Theme.of(context).platform == TargetPlatform.windows;
    final resumeWithTip = Tooltip(
      message: l10n.resumeBannerTooltip(command),
      child: resume,
    );
    // A1 §4: the primary button is on the right on macOS.
    final buttons = windows
        ? [resumeWithTip, dismiss]
        : [dismiss, resumeWithTip];
    return Focus(
      // Esc on a button of the banner is "Dismiss"; the banner itself never
      // asks for the focus.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        _dismiss();
        return KeyEventResult.handled;
      },
      child: Semantics(
        key: Key('resume.banner.${widget.pane}'),
        container: true,
        explicitChildNodes: true,
        label: text,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface.withValues(alpha: 0.95),
            border: const Border(
              bottom: BorderSide(color: ShellxDesktopColors.accent),
            ),
          ),
          child: Row(
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.history_rounded,
                  size: ShellxSizes.icon,
                  color: ShellxDesktopColors.accent,
                ),
              ),
              const SizedBox(width: ShellxSpace.s6),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellxText.body.copyWith(
                      color: ShellxDesktopColors.textPrimary,
                    ),
                  ),
                ),
              ),
              for (final b in buttons) ...[
                const SizedBox(width: ShellxSpace.s6),
                b,
              ],
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle({required bool primary}) => TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
    minimumSize: const Size(64, ShellxSizes.remoteStripButton),
    backgroundColor: primary
        ? ShellxDesktopColors.primary
        : ShellxDesktopColors.rowSelected,
    foregroundColor: primary
        ? ShellxDesktopColors.onPrimary
        : ShellxDesktopColors.textPrimary,
    textStyle: ShellxText.small.copyWith(fontWeight: FontWeight.w600),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ShellxRadius.r6),
    ),
  );
}
