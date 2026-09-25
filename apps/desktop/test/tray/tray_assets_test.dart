import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';

void main() {
  for (final icon in TrayIconState.values) {
    test(
      '${icon.name}: 36x36 PNG for macOS and a 16+32 px ICO for Windows',
      () {
        final png = File(trayIconAsset(icon, windows: false)).readAsBytesSync();
        expect(png.sublist(0, 8), [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]);
        final ihdr = ByteData.sublistView(png, 16, 24);
        expect(ihdr.getUint32(0), 36);
        expect(ihdr.getUint32(4), 36);

        final ico = ByteData.sublistView(
          File(trayIconAsset(icon, windows: true)).readAsBytesSync(),
        );
        expect(ico.getUint16(2, Endian.little), 1, reason: 'ICO type');
        expect(ico.getUint16(4, Endian.little), 2, reason: 'image count');
        expect(ico.getUint8(6), 16);
        expect(ico.getUint8(22), 32);
      },
    );
  }

  test('pubspec bundles the tray assets', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/tray/'));
  });
}
