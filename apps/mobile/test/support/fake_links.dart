import 'package:shellx_mobile/core/core.dart' hide test;

/// Records what the app tried to open outside itself.
class FakeExternalLinks implements ExternalLinks {
  final List<Uri> opened = [];
  int settingsOpened = 0;

  /// Thrown by [open] and [openAppSettings] after recording the call (e.g. a PlatformException).
  Object? error;

  /// What [open] answers: false when no app could open the link.
  bool openResult = true;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    final failure = error;
    if (failure != null) throw failure;
    return openResult;
  }

  @override
  Future<void> openAppSettings() async {
    settingsOpened++;
    final failure = error;
    if (failure != null) throw failure;
  }
}
