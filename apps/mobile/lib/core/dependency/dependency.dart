import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/dependency/dependency.config.dart';

final getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
  // A missing registration fails `build_runner` instead of crashing at launch.
  throwOnMissingDependencies: true,
)
FutureOr<GetIt> configureDependencies({String? environment}) {
  return getIt.init(environment: environment);
}

Future<void> resetDependencies({String? environment}) async {
  await getIt.reset();
  configureDependencies(environment: environment);
}
