import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/router/app_router.gr.dart';

@singleton
@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    // Placeholder home; Task 19 replaces it with the ShellX routes and their guards.
    AutoRoute(page: StartRoute.page, initial: true),
  ];
}
