// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:flutter/material.dart' as _i409;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:shared_preferences/shared_preferences.dart' as _i460;

import '../core.dart' as _i351;
import '../handler/popup_handler.dart' as _i695;
import '../router/app_router.dart' as _i81;
import 'module.dart' as _i946;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final module = _$Module();
    gh.singleton<_i81.AppRouter>(() => _i81.AppRouter());
    await gh.lazySingletonAsync<_i460.SharedPreferences>(
      () => module.sharedPref,
      preResolve: true,
    );
    gh.factory<_i409.BuildContext>(() => module.context(gh<_i81.AppRouter>()));
    gh.lazySingleton<_i695.PopupHandler>(
      () => _i695.PopupHandler(gh<_i351.BuildContext>()),
    );
    return this;
  }
}

class _$Module extends _i946.Module {}
