import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/architecture/error.dart';
import 'package:shellx_mobile/core/architecture/error_text.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Turns anything a guarded call throws into the [AppError] the user sees.
///
/// The title is always a spec §12 text (via [ErrorText]), never the thrown object's `toString()`:
/// API and relay failures can carry request details (overview §2).
class ErrorFactory {
  AppError fromException(Object e, {StackTrace? stackTrace}) {
    final title = ErrorText(S.current).describe(e);
    return switch (e) {
      ApiException(code: 'network') => NetworkError(title: title, originalError: e, stackTrace: stackTrace),
      ApiException(code: 'unauthorized') => UnauthorizedError(title: title, originalError: e, stackTrace: stackTrace),
      ApiException() ||
      PairingException() ||
      AppErrorException() ||
      MachineFailed() ||
      MachineConnectionException() => AppError(title: title, originalError: e, stackTrace: stackTrace),
      _ => UnknownError(title: title, originalError: e, stackTrace: stackTrace),
    };
  }
}
