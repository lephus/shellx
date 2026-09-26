import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/router/app_router.gr.dart';
import 'package:shellx_mobile/core/router/auth_guard.dart';
import 'package:shellx_mobile/core/router/update_guard.dart';

/// One flat stack: every page and every dialog lives on the root navigator, which is what the
/// terminal page's exit (`popUntil` past its sheets) and `showConfirmDialog` expect.
@singleton
@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  final AuthGuard authGuard;
  final UpdateGuard updateGuard;

  AppRouter({required this.authGuard, required this.updateGuard});

  @override
  List<AutoRoute> get routes => [
    // Public routes; an outdated app is sent to UpdateRequiredRoute first.
    AutoRoute(page: UpdateRequiredRoute.page),
    AutoRoute(page: LoginRoute.page, guards: [updateGuard]),
    AutoRoute(page: RegisterRoute.page, guards: [updateGuard]),

    // Signed-in routes - MachineListRoute is initial.
    AutoRoute(page: MachineListRoute.page, initial: true, guards: [updateGuard, authGuard]),
    AutoRoute(page: TerminalRoute.page, guards: [authGuard]),
    AutoRoute(page: QrScannerRoute.page, guards: [authGuard]),
    AutoRoute(page: SettingsRoute.page, guards: [authGuard]),
    AutoRoute(page: DeleteAccountRoute.page, guards: [authGuard]),
  ];
}
