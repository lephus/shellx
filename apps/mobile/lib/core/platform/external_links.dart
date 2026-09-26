import 'package:app_settings/app_settings.dart' as system;
import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

/// Leaves the app: a web page (store listing, terms) or the phone's settings for ShellX
/// (camera permission, design "Quét mã").
abstract interface class ExternalLinks {
  Future<bool> open(Uri url);

  Future<void> openAppSettings();
}

@LazySingleton(as: ExternalLinks)
final class UrlLauncherLinks implements ExternalLinks {
  @override
  Future<bool> open(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Future<void> openAppSettings() => system.AppSettings.openAppSettings();
}

/// For a tap on a link or a button: a platform that cannot open it (a `PlatformException`, no app
/// for the link) shows the [ErrorText] fallback as a toast instead of an unhandled error. Never
/// throws.
extension TappedExternalLinks on ExternalLinks {
  Future<void> openOrToast(Uri url) async {
    try {
      if (!await open(url)) _toast(StateError('No app opened the link'));
    } catch (error) {
      _toast(error);
    }
  }

  Future<void> openAppSettingsOrToast() async {
    try {
      await openAppSettings();
    } catch (error) {
      _toast(error);
    }
  }
}

/// Only the error's type is logged, never the link.
void _toast(Object error) {
  if (kDebugMode) debugPrint('ExternalLinks error: ${error.runtimeType}');
  getIt<PopupHandler>().showError(title: ErrorText(S.current).describe(error));
}
