import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../pages/change_password_page.dart';
import '../pages/confirm_page.dart';
import '../pages/login_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/pairing_page.dart';
import '../terminal/shortcut_labels.dart';
import '../terminal/ssh_connect_dialog.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';
import 'dialog_informational.dart';
import 'dialog_layout.dart';

/// UI §4 widths. The height follows the content (title → 8 → body → 24 →
/// actions), up to the window's room ([RouteDialogHost]).
double dialogWidthFor(WindowState state) {
  final confirm = state.confirm;
  if (confirm != null) {
    return confirm.long ? ShellxSizes.dialogWidthLong : ShellxSizes.dialogWidth;
  }
  return switch (state.route) {
    OnboardingRoute() => ShellxSizes.dialogWidthOnboarding,
    SshConnectRoute() => ShellxSizes.connectDialogWidth,
    LoginRoute() ||
    PairingRoute() ||
    ChangePasswordRoute() ||
    null => ShellxSizes.dialogWidth,
  };
}

/// The legacy route or confirm as a dialog over the terminal (UI §4):
/// scrim, focus trapped, Escape = close, informational dialogs (pairing,
/// change password once done) close on a scrim click, forms and confirms do
/// not. It is a named route for screen readers (UI §3.7). The dialog is as
/// tall as its page, up to the window's room (it can be as small as
/// 640×400, UI §2); then the page body scrolls ([DialogBody]).
/// Each new dialog comes in with the `base` scale 0.98→1 (UI §1.5; the
/// fades in and out are [WindowContent]'s).
class RouteDialogHost extends ConsumerStatefulWidget {
  const RouteDialogHost({super.key, required this.state});
  final WindowState state;

  @override
  ConsumerState<RouteDialogHost> createState() => _RouteDialogHostState();
}

class _RouteDialogHostState extends ConsumerState<RouteDialogHost>
    with SingleTickerProviderStateMixin {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'dialog');

  /// The `base` scale-in, restarted for each new dialog without rebuilding
  /// the content (a route page under a confirm keeps its state).
  late final AnimationController _scaleIn = AnimationController(
    vsync: this,
    duration: ShellxMotion.base,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.98,
    end: 1,
  ).animate(CurvedAnimation(parent: _scaleIn, curve: ShellxMotion.baseCurve));
  bool _doneInformational = false;

  Object get _identity =>
      widget.state.confirm ?? widget.state.route.runtimeType;

  @override
  void initState() {
    super.initState();
    _trapFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scaleIn.status == AnimationStatus.dismissed) _playScaleIn();
  }

  void _playScaleIn() {
    _scaleIn.duration = ShellxMotion.of(context, ShellxMotion.base);
    _scaleIn.forward(from: 0);
  }

  @override
  void didUpdateWidget(RouteDialogHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Per route: a confirm over a finished change-password (and cancelled)
    // leaves it finished; the route page stays mounted under the confirm.
    if (oldWidget.state.route.runtimeType != widget.state.route.runtimeType) {
      _doneInformational = false;
    }
    final before = oldWidget.state.confirm ?? oldWidget.state.route.runtimeType;
    if (before != _identity) _playScaleIn();
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
    _scaleIn.dispose();
    _scope.dispose();
    super.dispose();
  }

  String _title(AppLocalizations l10n) {
    final confirm = widget.state.confirm;
    if (confirm != null) return confirm.title;
    return switch (widget.state.route) {
      LoginRoute() => l10n.authSignInTitle,
      OnboardingRoute() => l10n.onboardingTitle,
      PairingRoute() => l10n.pairingTitle,
      ChangePasswordRoute() => l10n.changePasswordTitle,
      SshConnectRoute() => l10n.sshDialogTitle,
      null => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l10n = AppLocalizations.of(context);
    final router = ref.read(windowRouterProvider.notifier);
    final confirm = state.confirm;
    final Widget routePage = switch (state.route) {
      LoginRoute() => const LoginPage(),
      OnboardingRoute() => const OnboardingPage(),
      PairingRoute() => const PairingPage(),
      ChangePasswordRoute() => const ChangePasswordPage(),
      // A8 UI §4: the other forms' title, padding and scroll.
      SshConnectRoute(:final tab) => DialogBody(
        title: l10n.sshDialogTitle,
        content: [SshConnectDialog(initialTab: tab, showTitle: false)],
      ),
      null => const SizedBox.shrink(),
    };
    // A confirm over a route hides the route page but keeps it mounted, so
    // what was typed or finished there is still there after the confirm.
    // Offstage takes no room: the dialog is the shown page's height.
    final Widget page = Stack(
      children: [
        if (state.route != null)
          Offstage(
            offstage: confirm != null,
            child: TickerMode(
              enabled: confirm == null,
              child: ExcludeFocus(excluding: confirm != null, child: routePage),
            ),
          ),
        if (confirm != null)
          ConfirmPage(key: ValueKey(confirm), request: confirm),
      ],
    );
    final informational =
        confirm == null &&
        (state.route is PairingRoute ||
            (state.route is ChangePasswordRoute && _doneInformational));
    final screen = MediaQuery.sizeOf(context);
    final maxHeight = confirm?.long ?? false
        ? screen.height * 0.8
        : screen.height - 2 * ShellxSpace.s24;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
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
              child: ScaleTransition(
                scale: _scale,
                child: Theme(
                  data: buildDialogTheme(
                    Theme.of(context),
                    reduceMotion: reduceMotion,
                  ),
                  child: Semantics(
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: _title(l10n),
                    child: Container(
                      key: const Key('dialog'),
                      width: dialogWidthFor(state),
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: ShellxDesktopColors.surface,
                        borderRadius: BorderRadius.circular(ShellxRadius.r12),
                        border: Border.all(color: ShellxDesktopColors.border),
                        boxShadow: ShellxShadows.e2,
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child:
                            NotificationListener<
                              DialogInformationalNotification
                            >(
                              onNotification: (_) {
                                setState(() => _doneInformational = true);
                                return true;
                              },
                              child: Stack(
                                children: [
                                  page,
                                  if (!isMacDesktop)
                                    Positioned(
                                      // Centred on the 22 px title line
                                      // that starts 24 down (P-3).
                                      top:
                                          ShellxSpace.s24 +
                                          (ShellxSizes.dialogTitleLine -
                                                  ShellxSizes.iconHit) /
                                              2,
                                      right: ShellxSpace.s12,
                                      child: SizedBox.square(
                                        dimension: ShellxSizes.iconHit,
                                        child: IconButton(
                                          key: const Key('dialog.close'),
                                          padding: EdgeInsets.zero,
                                          tooltip: l10n.dialogClose,
                                          onPressed: router.close,
                                          icon: const Icon(
                                            Icons.close,
                                            size: ShellxSizes.icon,
                                            color: ShellxDesktopColors
                                                .textSecondary,
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
          ),
        ),
      ],
    );
  }
}
