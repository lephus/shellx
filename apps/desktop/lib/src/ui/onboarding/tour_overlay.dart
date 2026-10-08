import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/keybind_actions.dart';
import '../config/action_labels.dart';
import '../terminal/shortcut_labels.dart';
import '../terminal/terminal_overlays.dart' show ShellxPrimaryButton;
import '../theme/shellx_desktop_theme.dart';

/// The words of a tour step for [action]: its chord as it is bound now (a
/// rebind shows the real one) or, when the action is unbound, its name, so
/// a sentence never has a hole in it (A9 D29).
String hintFor(AppLocalizations l10n, KeyAction action) =>
    actionShortcutLabel(action) ?? actionLabel(l10n, action);

/// A11 D24: the four cards of the first-run tour. Blocks the window like
/// Settings (a scrim, focus kept inside, Esc skips) but holds no state of
/// the app: [onFinish] is called for Skip, Esc and Done alike.
class TourOverlay extends ConsumerStatefulWidget {
  const TourOverlay({super.key, required this.onFinish});
  final VoidCallback onFinish;

  @override
  ConsumerState<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends ConsumerState<TourOverlay> {
  static const int _steps = 4;
  int _index = 0;
  final _next = FocusNode(debugLabel: 'tour next');

  @override
  void dispose() {
    _next.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0 || to >= _steps || to == _index) return;
    setState(() => _index = to);
    // A screen reader hears the new step without moving the focus.
    final l10n = AppLocalizations.of(context);
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.tourStep(to + 1, _steps),
      Directionality.of(context),
    );
  }

  void _advance() => _index == _steps - 1 ? widget.onFinish() : _go(_index + 1);

  ({IconData icon, String title, String body}) _step(AppLocalizations l10n) {
    String h(String name, [String? param]) =>
        hintFor(l10n, KeyAction(name, param));
    return switch (_index) {
      0 => (
        icon: Icons.tab,
        title: l10n.tourTabsTitle,
        body: l10n.tourTabsBody(
          h('new_tab'),
          h('new_split', 'right'),
          h('new_split', 'down'),
        ),
      ),
      1 => (
        icon: Icons.notifications_active_outlined,
        title: l10n.tourNotifyTitle,
        body: l10n.tourNotifyBody(h('jump_to_unread')),
      ),
      2 => (
        icon: Icons.search,
        title: l10n.tourFindTitle,
        body: l10n.tourFindBody(
          h('start_search'),
          h('search_all'),
          h('toggle_command_palette'),
        ),
      ),
      _ => (
        icon: Icons.tune,
        title: l10n.tourSettingsTitle,
        body: l10n.tourSettingsBody(h('open_settings')),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    // The chords follow a reload (A9 D29).
    ref.watch(shellxConfigProvider.select((s) => s.bindings));
    final l10n = AppLocalizations.of(context);
    final step = _step(l10n);
    final last = _index == _steps - 1;
    final size = MediaQuery.sizeOf(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.tourLabel,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onFinish,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _go(_index - 1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _go(_index + 1),
        },
        child: FocusScope(
          autofocus: true,
          child: Container(
            key: const Key('tour.card'),
            width: (size.width - 48).clamp(280.0, 440.0),
            padding: const EdgeInsets.all(ShellxSpace.s16),
            decoration: BoxDecoration(
              color: ShellxDesktopColors.surface,
              borderRadius: BorderRadius.circular(ShellxRadius.r8),
              border: Border.all(color: ShellxDesktopColors.border),
              boxShadow: ShellxShadows.e1,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      step.icon,
                      size: 28,
                      color: ShellxDesktopColors.primary,
                    ),
                  ),
                  const SizedBox(height: ShellxSpace.s12),
                  Semantics(
                    header: true,
                    child: Text(
                      step.title,
                      key: const Key('tour.title'),
                      style: ShellxText.emptyTitle.copyWith(
                        color: ShellxDesktopColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: ShellxSpace.s6),
                  Text(
                    step.body,
                    key: const Key('tour.body'),
                    style: ShellxText.body.copyWith(
                      color: ShellxDesktopColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: ShellxSpace.s16),
                  Row(
                    children: [
                      Semantics(
                        label: l10n.tourStep(_index + 1, _steps),
                        liveRegion: true,
                        excludeSemantics: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < _steps; i++)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == _index
                                      ? ShellxDesktopColors.primary
                                      : ShellxDesktopColors.border,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (!last)
                        TextButton(
                          key: const Key('tour.skip'),
                          onPressed: widget.onFinish,
                          child: Text(l10n.tourSkip),
                        ),
                      if (_index > 0)
                        TextButton(
                          key: const Key('tour.back'),
                          onPressed: () => _go(_index - 1),
                          child: Text(l10n.tourBack),
                        ),
                      const SizedBox(width: ShellxSpace.s8),
                      ShellxPrimaryButton(
                        key: const Key('tour.next'),
                        label: last ? l10n.tourDone : l10n.tourNext,
                        onPressed: _advance,
                        focusNode: _next,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // The primary button has the keyboard: Enter is Next / Done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _next.requestFocus();
    });
  }
}
