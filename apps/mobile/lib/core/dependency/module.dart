import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/config/app_config.dart';
import 'package:shellx_mobile/core/platform/device_description.dart';
import 'package:shellx_mobile/core/platform/fresh_install.dart';
import 'package:shellx_mobile/core/platform/secure_key_value_store.dart';
import 'package:shellx_mobile/core/router/app_router.dart';

@module
abstract class Module {
  @lazySingleton
  @preResolve
  Future<SharedPreferences> get sharedPref => SharedPreferences.getInstance();

  /// The one [KeyValueStore] of the app (overview §5.5). The first launch of a fresh install
  /// wipes the Keychain before anything reads it (spec §5.1).
  @lazySingleton
  @preResolve
  Future<KeyValueStore> keyValueStore(SharedPreferences prefs) async {
    final store = SecureKeyValueStore();
    await wipeSecureStorageOnFreshInstall(prefs: prefs, wipe: store.deleteAll);
    return store;
  }

  @lazySingleton
  @preResolve
  Future<DeviceDescription> get deviceDescription => describeThisDevice();

  @lazySingleton
  @preResolve
  Future<PackageInfo> get packageInfo => PackageInfo.fromPlatform();

  /// REST goes only through `shellx_core` (`package:http`), never through a second HTTP stack.
  @lazySingleton
  ShellxApi get api => ShellxApi(baseUri: AppConfig.relayBaseUri);

  @injectable
  BuildContext context(AppRouter appRouter) {
    final context = appRouter.navigatorKey.currentContext!;
    return context;
  }
}
