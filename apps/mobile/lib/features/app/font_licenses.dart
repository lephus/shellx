import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Both bundled fonts are SIL OFL 1.1, whose text must ship with them (Settings → licences).
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['JetBrains Mono'], await rootBundle.loadString(Assets.licenses.jetBrainsMonoOFL));
    yield LicenseEntryWithLineBreaks(['Raleway'], await rootBundle.loadString(Assets.licenses.ralewayOFL));
  });
}
