import 'package:app_settings/app_settings.dart' as system;
import 'package:injectable/injectable.dart';
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
