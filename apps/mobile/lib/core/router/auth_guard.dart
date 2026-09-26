import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/auth/session_holder.dart';
import 'package:shellx_mobile/core/router/app_router.gr.dart';

/// Signed-in pages need a session (spec §9.2 #1).
@injectable
class AuthGuard extends AutoRouteGuard {
  final SessionHolder sessionHolder;

  AuthGuard(this.sessionHolder);

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (sessionHolder.isAuthenticated.peek()) {
      resolver.next(true);
    } else {
      router.replace(const LoginRoute());
      resolver.next(false);
    }
  }
}
