import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/clipboard_media.dart';

void main() {
  test('a copied web link is not a file; real paths are kept', () async {
    final dir = Directory.systemTemp.createTempSync('clip');
    addTearDown(() => dir.deleteSync(recursive: true));
    final real = File('${dir.path}/cat.png')..writeAsBytesSync([1]);
    final media = SystemClipboardMedia(
      // macOS reads a copied `https://host/cat.png` as the path `/cat.png`.
      readFiles: () async => ['/cat.png', real.path, dir.path],
    );
    expect(await media.files(), [real.path, dir.path]);
  });

  test('a failing or hanging plugin is no files', () async {
    final failing = SystemClipboardMedia(
      readFiles: () async => throw StateError('no plugin'),
    );
    expect(await failing.files(), isEmpty);
  });
}
