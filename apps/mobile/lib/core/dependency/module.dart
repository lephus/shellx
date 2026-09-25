import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_mobile/core/router/app_router.dart';

@module
abstract class Module {
  @lazySingleton
  @preResolve
  Future<SharedPreferences> get sharedPref => SharedPreferences.getInstance();

  @injectable
  BuildContext context(AppRouter appRouter) {
    final context = appRouter.navigatorKey.currentContext!;
    return context;
  }
}
