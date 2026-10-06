import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../pages/change_password_page.dart';
import '../pages/confirm_page.dart';
import '../pages/login_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/pairing_page.dart';
import '../terminal/shortcut_labels.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';

/// UI §4 widths; heights are the old fixed windows' (the page bodies are
/// reused as they are and lay out for them).
Size dialogSizeFor(WindowState state) {
  final confirm = state.confirm;
  if (confirm != null) {
    return confirm.long
        ? const Size(ShellxSizes.dialogWidthLong, 560)
        : const Size(ShellxSizes.dialogWidth, 260);
  }
  return switch (state.route) {
    LoginRoute() => const Size(ShellxSizes.dialogWidth, 620),
    OnboardingRoute() => const Size(ShellxSizes.dialogWidthOnboarding, 660),
    PairingRoute() => const Size(ShellxSizes.dialogWidth, 660),
    ChangePasswordRoute() => const Size(ShellxSizes.dialogWidth, 480),
    null => const Size(ShellxSizes.dialogWidth, 260),
  };
}

/// UI §2: "{tab} — ShellX", or "ShellX" with no tabs.
String windowTitleFor(TerminalTab? selected, AppLocalizations l10n) =>
    selected == null ? 'ShellX' : l10n.windowTitle(selected.label);

/// The legacy route or confirm as a dialog over the terminal (UI §4):
/// scrim, focus trapped, Escape = close, informational dialogs (pairing)
/// close on a scrim click, forms and confirms do not. It comes in with the
/// `base` fade + scale 0.98→1 (UI §1.5).
class RouteDialogHost extends ConsumerStatefulWidget {
  const RouteDialogHost({super.key, required this.state});
  final WindowState state;

  @override
  ConsumerState<RouteDialogHost> createState() => _RouteDialogHostState();
}

class _RouteDialogHostState extends ConsumerState<RouteDialogHost> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'dialog');

  @override
  void initState() {
    super.initState();
    _trapFocus();
  }

  @override
  void didUpdateWidget(RouteDialogHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _trapFocus();
  }

  /// After the frame (the page's own autofocus runs first): the terminal
  /// behind is excluded from focus, so keys must land in the dialog.
  void _trapFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final router = ref.read(windowRouterProvider.notifier);
    final confirm = state.confirm;
    final Widget page = confirm != null
        ? ConfirmPage(key: ValueKey(confirm), request: confirm)
        : switch (state.route) {
            LoginRoute() => const LoginPage(),
            OnboardingRoute() => const OnboardingPage(),
            PairingRoute() => const PairingPage(),
            ChangePasswordRoute() => const ChangePasswordPage(),
            null => const SizedBox.shrink(),
          };
    final informational = confirm == null && state.route is PairingRoute;
    final screen = MediaQuery.sizeOf(context);
    final size = dialogSizeFor(state);
    final maxHeight = confirm?.long ?? false
        ? screen.height * 0.8
        : screen.height - 2 * ShellxSpace.s24;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final Object identity = confirm ?? state.route.runtimeType;
    return Stack(
      children: [
        Positioned.fill(
          child: ModalBarrier(
            color: ShellxDesktopColors.scrim,
            dismissible: informational,
            onDismiss: router.close,
          ),
        ),
        Center(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): router.close,
            },
            child: FocusScope(
              node: _scope,
              autofocus: true,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(identity),
                tween: Tween(begin: 0, end: 1),
                duration: ShellxMotion.of(context, ShellxMotion.base),
                curve: ShellxMotion.baseCurve,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
                ),
                child: Theme(
                  data: buildDialogTheme(
                    Theme.of(context),
                    reduceMotion: reduceMotion,
                  ),
                  child: Container(
                    key: const Key('dialog'),
                    width: size.width,
                    height: min(size.height, maxHeight),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: ShellxDesktopColors.surface,
                      borderRadius: BorderRadius.circular(ShellxRadius.r12),
                      border: Border.all(color: ShellxDesktopColors.border),
                      boxShadow: ShellxShadows.e2,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        children: [
                          Positioned.fill(child: page),
                          if (!isMacDesktop)
                            Positioned(
                              top: ShellxSpace.s12,
                              right: ShellxSpace.s12,
                              child: SizedBox.square(
                                dimension: ShellxSizes.iconHit,
                                child: IconButton(
                                  key: const Key('dialog.close'),
                                  padding: EdgeInsets.zero,
                                  tooltip: AppLocalizations.of(
                                    context,
                                  ).dialogClose,
                                  onPressed: router.close,
                                  icon: const Icon(
                                    Icons.close,
                                    size: ShellxSizes.icon,
                                    color: ShellxDesktopColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
