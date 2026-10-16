import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// `flutter test` runs with the package root (apps/desktop) as the working directory.
const String _macIcons = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
const String _windowsIcon = 'windows/runner/resources/app_icon.ico';

/// The ShellX tile is a dark gradient (#1C1438 to #0B0716, with a faint mint
/// glow): every channel stays this dark, so it is told apart from the Flutter default.
const int _tileMax = 0x40;

Future<({int width, int height, ByteData rgba})> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData())!;
  return (width: image.width, height: image.height, rgba: rgba);
}

List<int> _pixel(({int width, int height, ByteData rgba}) image, int x, int y) {
  final offset = (y * image.width + x) * 4;
  return [for (var i = 0; i < 4; i++) image.rgba.getUint8(offset + i)];
}

void main() {
  test(
    'macOS AppIcon: every size is the ShellX tile on a transparent margin',
    () async {
      for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
        final image = await _decode('$_macIcons/app_icon_$size.png');
        expect((image.width, image.height), (size, size), reason: '$size');
        expect(
          _pixel(image, 0, 0)[3],
          0,
          reason: 'corner of $size is transparent',
        );
        if (size < 128) continue;
        // Just inside the tile's left edge, level with the top dots: the dark tile.
        final inside = _pixel(
          image,
          (size * 0.2).round(),
          (size * 0.2).round(),
        );
        for (var i = 0; i < 3; i++) {
          expect(inside[i], lessThan(_tileMax), reason: '$size channel $i');
        }
        expect(inside[3], 255, reason: '$size');
      }
    },
  );

  test('Windows app_icon.ico carries 16 to 256 px images', () {
    final bytes = File(_windowsIcon).readAsBytesSync();
    final header = ByteData.sublistView(bytes);
    expect(header.getUint16(2, Endian.little), 1, reason: 'ICO type');
    final count = header.getUint16(4, Endian.little);
    final sizes = {
      for (var i = 0; i < count; i++)
        // Width byte 0 means 256.
        bytes[6 + i * 16] == 0 ? 256 : bytes[6 + i * 16],
    };
    expect(sizes, containsAll(<int>[16, 24, 32, 48, 64, 128, 256]));
  });

  test(
    'the Windows 256 px image is the ShellX tile, not the Flutter default',
    () async {
      final bytes = File(_windowsIcon).readAsBytesSync();
      final header = ByteData.sublistView(bytes);
      final count = header.getUint16(4, Endian.little);
      for (var i = 0; i < count; i++) {
        final entry = 6 + i * 16;
        if (bytes[entry] != 0) continue;
        final length = header.getUint32(entry + 8, Endian.little);
        final offset = header.getUint32(entry + 12, Endian.little);
        final png = bytes.sublist(offset, offset + length);
        final path =
            '${Directory.systemTemp.createTempSync('shellx_icon').path}/256.png';
        File(path).writeAsBytesSync(png);
        final image = await _decode(path);
        expect(_pixel(image, 0, 0)[3], 0);
        // Left of the prompt, half way down: the dark tile.
        final inside = _pixel(image, 30, 128);
        for (var c = 0; c < 3; c++) {
          expect(inside[c], lessThan(_tileMax));
        }
        return;
      }
      fail('no 256 px image');
    },
  );
}
