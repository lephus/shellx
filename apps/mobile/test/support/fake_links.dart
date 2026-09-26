import 'package:shellx_mobile/core/core.dart' hide test;

/// Records what the app tried to open outside itself.
class FakeExternalLinks implements ExternalLinks {
  final List<Uri> opened = [];
  int settingsOpened = 0;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }

  @override
  Future<void> openAppSettings() async => settingsOpened++;
}
