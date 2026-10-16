import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// JetBrains Mono is SIL OFL 1.1, whose text must ship with it.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/licenses/JetBrainsMono-OFL.txt'));
  });
}
