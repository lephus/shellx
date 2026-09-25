import 'package:shellx_mobile/core/architecture/error.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Turns anything a guarded call throws into the [AppError] the user sees.
///
/// The title is always a localized text, never the thrown object's `toString()`: API and relay
/// failures can carry request details (overview §2).
class ErrorFactory {
  AppError fromException(Object e, {StackTrace? stackTrace}) {
    return UnknownError(
      title: S.current.somethingWentWrongPleaseTryAgain,
      stackTrace: stackTrace,
      originalError: e,
    );
  }
}
