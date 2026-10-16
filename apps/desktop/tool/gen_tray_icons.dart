// Generates the tray icons in assets/tray/ (no dependencies beyond dart:io).
// Run from apps/desktop:  dart run tool/gen_tray_icons.dart
//
// Glyph: a rounded square with a ">_" prompt.
// macOS PNG 36x36 (18 pt @2x): normal/offline are template images (black,
// offline at 35 % alpha → rendered grey by the menu bar); active is green.
// Windows ICO (16x16 + 32x32, 32-bit DIB): blue / grey / green.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

typedef Rgba = (int r, int g, int b, int a);

double _segmentDistance(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax, dy = by - ay;
  final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(
    0.0,
    1.0,
  );
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

double _roundedRectDistance(double px, double py) {
  // Signed distance to a rounded square centred at 0.5, half-size 0.42, radius 0.18.
  const half = 0.42, radius = 0.18;
  final qx = (px - 0.5).abs() - (half - radius);
  final qy = (py - 0.5).abs() - (half - radius);
  final outside = math.sqrt(
    math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2),
  );
  return outside + math.min(math.max(qx, qy), 0.0) - radius;
}

bool _inside(double x, double y) {
  const stroke = 0.09;
  if (_roundedRectDistance(x, y).abs() < stroke / 2) return true;
  if (_segmentDistance(x, y, 0.28, 0.34, 0.46, 0.5) < stroke / 2) return true;
  if (_segmentDistance(x, y, 0.46, 0.5, 0.28, 0.66) < stroke / 2) return true;
  return _segmentDistance(x, y, 0.54, 0.67, 0.74, 0.67) < stroke / 2;
}

/// RGBA pixels, row-major, top row first; 4x4 supersampling for anti-aliasing.
Uint8List render(int size, Rgba color) {
  final pixels = Uint8List(size * size * 4);
  const samples = 4;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var hits = 0;
      for (var sy = 0; sy < samples; sy++) {
        for (var sx = 0; sx < samples; sx++) {
          if (_inside(
            (x + (sx + 0.5) / samples) / size,
            (y + (sy + 0.5) / samples) / size,
          )) {
            hits++;
          }
        }
      }
      final i = (y * size + x) * 4;
      pixels[i] = color.$1;
      pixels[i + 1] = color.$2;
      pixels[i + 2] = color.$3;
      pixels[i + 3] = (color.$4 * hits / (samples * samples)).round();
    }
  }
  return pixels;
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final out = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(body)
    ..add((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
  return out.takeBytes();
}

Uint8List encodePng(int size, Uint8List rgba) {
  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // colour type RGBA
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // filter: none
    raw.add(rgba.sublist(y * size * 4, (y + 1) * size * 4));
  }
  return (BytesBuilder()
        ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(_chunk('IHDR', header.buffer.asUint8List()))
        ..add(_chunk('IDAT', ZLibEncoder().convert(raw.takeBytes())))
        ..add(_chunk('IEND', const [])))
      .takeBytes();
}

/// One 32-bit BGRA DIB icon image (BITMAPINFOHEADER + XOR bitmap + AND mask).
Uint8List _dib(int size, Uint8List rgba) {
  final maskRowBytes = ((size + 31) ~/ 32) * 4;
  final info = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, size, Endian.little)
    ..setInt32(8, size * 2, Endian.little) // XOR + AND
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 32, Endian.little)
    ..setUint32(20, size * size * 4 + maskRowBytes * size, Endian.little);
  final out = BytesBuilder()..add(info.buffer.asUint8List());
  for (var y = size - 1; y >= 0; y--) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      out.add([rgba[i + 2], rgba[i + 1], rgba[i], rgba[i + 3]]);
    }
  }
  out.add(Uint8List(maskRowBytes * size)); // all zero: alpha channel decides
  return out.takeBytes();
}

Uint8List encodeIco(Rgba color) {
  const sizes = [16, 32];
  final images = [for (final s in sizes) _dib(s, render(s, color))];
  final header = ByteData(6 + 16 * sizes.length)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, sizes.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < sizes.length; i++) {
    final entry = 6 + 16 * i;
    header
      ..setUint8(entry, sizes[i])
      ..setUint8(entry + 1, sizes[i])
      ..setUint16(entry + 4, 1, Endian.little)
      ..setUint16(entry + 6, 32, Endian.little)
      ..setUint32(entry + 8, images[i].length, Endian.little)
      ..setUint32(entry + 12, offset, Endian.little);
    offset += images[i].length;
  }
  final out = BytesBuilder()..add(header.buffer.asUint8List());
  for (final image in images) {
    out.add(image);
  }
  return out.takeBytes();
}

void main() {
  const mac = <String, Rgba>{
    'normal': (0, 0, 0, 255),
    'offline': (0, 0, 0, 90),
    'active': (0x22, 0xC5, 0x5E, 255),
  };
  const windows = <String, Rgba>{
    'normal': (0x3B, 0x82, 0xF6, 255),
    'offline': (0x9C, 0xA3, 0xAF, 255),
    'active': (0x22, 0xC5, 0x5E, 255),
  };
  final dir = Directory('assets/tray')..createSync(recursive: true);
  for (final name in mac.keys) {
    File(
      '${dir.path}/tray_$name.png',
    ).writeAsBytesSync(encodePng(36, render(36, mac[name]!)));
    File(
      '${dir.path}/tray_$name.ico',
    ).writeAsBytesSync(encodeIco(windows[name]!));
  }
  stdout.writeln('Wrote ${mac.length * 2} icons to ${dir.path}');
}
