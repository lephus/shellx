import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppRouteObserver extends AutoRouterObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    if (kDebugMode) debugPrint('Router pushed: ${route.settings.name}');
  }

  // only override to observer tab routes
  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) {
    if (kDebugMode) debugPrint('Router visited: ${route.name}');
  }

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) {
    if (kDebugMode) debugPrint('Tab Router re-visited: ${route.name}');
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (kDebugMode) debugPrint('Router didPop: ${route.settings.name}');
  }
}
