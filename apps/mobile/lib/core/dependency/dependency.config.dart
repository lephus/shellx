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
import 'package:package_info_plus/package_info_plus.dart' as _i655;
import 'package:shared_preferences/shared_preferences.dart' as _i460;
import 'package:shellx_core/shellx_core.dart' as _i145;

import '../../features/auth/presentation/controllers/login_controller.dart'
    as _i729;
import '../../features/auth/presentation/controllers/register_controller.dart'
    as _i145;
import '../../features/lock/domain/biometric_authenticator.dart' as _i870;
import '../../features/lock/presentation/app_lock_controller.dart' as _i306;
import '../../features/machines/presentation/controllers/machine_list_controller.dart'
    as _i70;
import '../../features/pairing/presentation/controllers/qr_scanner_controller.dart'
    as _i1044;
import '../../features/settings/presentation/controllers/delete_account_controller.dart'
    as _i907;
import '../../features/settings/presentation/controllers/settings_controller.dart'
    as _i1035;
import '../../features/terminal/presentation/controllers/terminal_page_controller.dart'
    as _i229;
import '../../features/terminal/presentation/controllers/terminal_workspace.dart'
    as _i667;
import '../auth/auth_event.dart' as _i909;
import '../auth/auth_storage.dart' as _i657;
import '../auth/session_enforcer.dart' as _i954;
import '../auth/session_holder.dart' as _i56;
import '../backend/backend.dart' as _i120;
import '../backend/client_backend.dart' as _i139;
import '../core.dart' as _i351;
import '../handler/popup_handler.dart' as _i695;
import '../platform/device_description.dart' as _i814;
import '../platform/external_links.dart' as _i618;
import '../router/app_router.dart' as _i81;
import '../router/auth_guard.dart' as _i313;
import '../router/update_guard.dart' as _i56;
import '../settings/app_settings.dart' as _i620;
import '../version/version_gate.dart' as _i505;
import 'module.dart' as _i946;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final module = _$Module();
    gh.lazySingleton<_i909.AuthEventNotifier>(() => _i909.AuthEventNotifier());
    await gh.lazySingletonAsync<_i460.SharedPreferences>(
      () => module.sharedPref,
      preResolve: true,
    );
    await gh.lazySingletonAsync<_i814.DeviceDescription>(
      () => module.deviceDescription,
      preResolve: true,
    );
    await gh.lazySingletonAsync<_i655.PackageInfo>(
      () => module.packageInfo,
      preResolve: true,
    );
    gh.lazySingleton<_i145.ShellxApi>(() => module.api);
    gh.lazySingleton<_i505.VersionGate>(
      () => _i505.VersionGate(gh<_i145.ShellxApi>(), gh<_i655.PackageInfo>()),
    );
    gh.lazySingleton<_i870.BiometricAuthenticator>(
      () => _i870.LocalAuthBiometricAuthenticator(),
    );
    gh.lazySingleton<_i618.ExternalLinks>(() => _i618.UrlLauncherLinks());
    await gh.lazySingletonAsync<_i145.KeyValueStore>(
      () => module.keyValueStore(gh<_i460.SharedPreferences>()),
      preResolve: true,
    );
    gh.lazySingleton<_i120.BackendFactory>(
      () => _i139.ClientBackendFactory(
        gh<_i145.ShellxApi>(),
        gh<_i145.KeyValueStore>(),
        gh<_i814.DeviceDescription>(),
        gh<_i655.PackageInfo>(),
      ),
    );
    gh.factory<_i56.UpdateGuard>(
      () => _i56.UpdateGuard(gh<_i505.VersionGate>()),
    );
    gh.lazySingleton<_i657.AuthStorage>(
      () => _i657.AuthStorageImpl(gh<_i145.KeyValueStore>()),
    );
    await gh.lazySingletonAsync<_i620.AppSettings>(() {
      final i = _i620.AppSettings(gh<_i145.KeyValueStore>());
      return i.load().then((_) => i);
    }, preResolve: true);
    gh.lazySingleton<_i56.SessionHolder>(
      () => _i56.SessionHolderImpl(
        api: gh<_i145.ShellxApi>(),
        storage: gh<_i351.AuthStorage>(),
        store: gh<_i145.KeyValueStore>(),
        device: gh<_i351.DeviceDescription>(),
        packageInfo: gh<_i655.PackageInfo>(),
        backends: gh<_i351.BackendFactory>(),
        events: gh<_i351.AuthEventNotifier>(),
      ),
    );
    gh.lazySingleton<_i306.AppLockController>(
      () => _i306.AppLockController.create(
        gh<_i870.BiometricAuthenticator>(),
        gh<_i351.AppSettings>(),
      ),
    );
    gh.factory<_i1044.QrScannerController>(
      () => _i1044.QrScannerController(gh<_i351.SessionHolder>()),
    );
    gh.factory<_i907.DeleteAccountController>(
      () => _i907.DeleteAccountController(gh<_i351.SessionHolder>()),
    );
    gh.factory<_i313.AuthGuard>(
      () => _i313.AuthGuard(gh<_i56.SessionHolder>()),
    );
    gh.factory<_i729.LoginController>(
      () => _i729.LoginController(gh<_i351.SessionHolder>()),
    );
    gh.factory<_i145.RegisterController>(
      () => _i145.RegisterController(gh<_i351.SessionHolder>()),
    );
    gh.singleton<_i81.AppRouter>(
      () => _i81.AppRouter(
        authGuard: gh<_i313.AuthGuard>(),
        updateGuard: gh<_i56.UpdateGuard>(),
      ),
    );
    gh.lazySingleton<_i667.WorkspaceRegistry>(
      () => _i667.WorkspaceRegistry.create(gh<_i351.SessionHolder>()),
      dispose: (i) => i.dispose(),
    );
    gh.factory<_i409.BuildContext>(() => module.context(gh<_i81.AppRouter>()));
    gh.factoryParam<_i229.TerminalPageController, String, dynamic>(
      (agentId, _) => _i229.TerminalPageController(
        agentId,
        gh<_i667.WorkspaceRegistry>(),
        gh<_i351.SessionHolder>(),
        gh<_i351.AppSettings>(),
      ),
    );
    gh.singleton<_i954.SessionEnforcer>(
      () => _i954.SessionEnforcerImpl(
        gh<_i351.AuthEventNotifier>(),
        gh<_i351.AppRouter>(),
      )..initialize(),
      dispose: (i) => i.dispose(),
    );
    gh.factory<_i70.MachineListController>(
      () => _i70.MachineListController.create(
        gh<_i351.SessionHolder>(),
        gh<_i667.WorkspaceRegistry>(),
      ),
    );
    gh.factory<_i1035.SettingsController>(
      () => _i1035.SettingsController(
        gh<_i351.SessionHolder>(),
        gh<_i351.AppSettings>(),
        gh<_i306.AppLockController>(),
        gh<_i870.BiometricAuthenticator>(),
        gh<_i667.WorkspaceRegistry>(),
        gh<_i655.PackageInfo>(),
      ),
    );
    gh.lazySingleton<_i695.PopupHandler>(
      () => _i695.PopupHandler(gh<_i351.BuildContext>()),
    );
    return this;
  }
}

class _$Module extends _i946.Module {}
