import 'package:shellx_mobile/core/architecture/error_factory.dart';

abstract class Repository {
  ErrorFactory get errorFactory {
    _errorFactory ??= ErrorFactory();
    return _errorFactory!;
  }

  ErrorFactory? _errorFactory;

  Future<T> resultGuard<T>(Future<T> Function() func) async {
    try {
      return await func();
    } catch (e, stackTrace) {
      throw errorFactory.fromException(e, stackTrace: stackTrace);
    }
  }

  Future<void> noResultGuard(Future<void> Function() func) async {
    try {
      await func();
    } catch (e, stackTrace) {
      throw errorFactory.fromException(e, stackTrace: stackTrace);
    }
  }
}
