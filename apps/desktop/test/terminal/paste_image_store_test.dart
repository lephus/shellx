import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/paste_image_store.dart';

Uint8List png([int extra = 0]) => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  ...List.filled(extra, 7),
]);

String mode(String path) =>
    (Process.runSync('stat', [
              ...(Platform.isMacOS ? ['-f', '%Lp'] : ['-c', '%a']),
              path,
            ]).stdout
            as String)
        .trim();

void main() {
  late Directory base;
  var now = DateTime(2026, 10, 7, 9, 5, 3);
  late PasteImageStore store;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('paste_images');
    now = DateTime(2026, 10, 7, 9, 5, 3);
    store = PasteImageStore(base, now: () => now);
  });
  tearDown(() => base.delete(recursive: true));

  test('the extension follows the first bytes', () {
    expect(imageExtension(png()), 'png');
    expect(imageExtension(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'jpg');
    expect(imageExtension(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])), 'gif');
    expect(imageExtension(Uint8List.fromList([0x42, 0x4D, 0, 0])), 'bmp');
    expect(
      imageExtension(Uint8List.fromList([0x49, 0x49, 0x2A, 0x00])),
      'tiff',
    );
    expect(imageExtension(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  test('saves a timestamped file with the right extension', () async {
    final path = await store.save(png());
    expect(path, matches(RegExp(r'paste-20261007-090503-[0-9a-f]{8}\.png$')));
    expect(File(path).readAsBytesSync(), png());
  });

  test('0700 folder, 0600 file', () async {
    final path = await store.save(png());
    expect(mode(store.directory.path), '700');
    expect(mode(path), '600');
  }, testOn: '!windows');

  test(
    'too large, empty and not-an-image are refused; nothing is written',
    () async {
      await expectLater(
        store.save(Uint8List(kMaxPasteImageBytes + 1)..[0] = 0x89),
        throwsA(isA<PasteImageTooLarge>()),
      );
      await expectLater(
        store.save(Uint8List(0)),
        throwsA(isA<PasteImageUnreadable>()),
      );
      await expectLater(
        store.save(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<PasteImageUnreadable>()),
      );
      expect(store.directory.existsSync(), isFalse);
    },
  );

  test('files older than 24 hours go when the next one is saved', () async {
    final old = await store.save(png());
    File(old).setLastModifiedSync(now.subtract(const Duration(hours: 25)));
    final fresh = await store.save(png(1));
    expect(File(old).existsSync(), isFalse);
    expect(File(fresh).existsSync(), isTrue);
  });

  test('at most 50 are kept, the oldest first to go', () async {
    final paths = <String>[];
    for (var i = 0; i < 52; i++) {
      final path = await store.save(png(i));
      File(path).setLastModifiedSync(now.subtract(Duration(minutes: 100 - i)));
      paths.add(path);
    }
    final left = store.directory.listSync().whereType<File>().length;
    expect(left, lessThanOrEqualTo(kMaxPasteImageFiles));
    expect(File(paths.first).existsSync(), isFalse);
    expect(File(paths.last).existsSync(), isTrue);
  });

  test('deleteAll empties the folder', () async {
    await store.save(png());
    await store.deleteAll();
    expect(store.directory.existsSync(), isFalse);
  });

  test('a failing chmod refuses the file and leaves none', () async {
    final failing = PasteImageStore(
      base,
      now: () => now,
      posix: true,
      chmod: (mode, paths) async => mode != '600',
    );
    await expectLater(failing.save(png()), throwsA(isA<FileSystemException>()));
    expect(failing.directory.listSync(), isEmpty);
  });

  test('a planted symlink in place of the folder is refused', () async {
    final target = await Directory.systemTemp.createTemp('paste_target');
    addTearDown(() => target.delete(recursive: true));
    await Link(store.directory.path).create(target.path);
    await expectLater(store.save(png()), throwsA(isA<FileSystemException>()));
    expect(target.listSync(), isEmpty);
    await store.deleteAll();
    expect(target.existsSync(), isTrue);
  }, testOn: '!windows');
}
