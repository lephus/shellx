import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal_sharing/config_text.dart';
import 'package:shellx_desktop/src/terminal_sharing/shell_blocks.dart';

const String block = '# >>> ShellX >>>\necho wrapped\n# <<< ShellX <<<\n';

Uint8List utf16(String text, {required bool littleEndian, bool bom = true}) {
  final out = BytesBuilder();
  if (bom) out.add(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]);
  for (final unit in text.codeUnits) {
    final lo = unit & 0xFF, hi = unit >> 8;
    out.add(littleEndian ? [lo, hi] : [hi, lo]);
  }
  return out.toBytes();
}

void main() {
  group('blocks', () {
    // Spec §5.2: the installer writes exactly the canonical blocks.
    for (final (name, text) in [
      ('block.zsh', zshBlock),
      ('block.bash', bashBlock),
      ('block.ps1', powerShellBlock),
    ]) {
      test('$name equals term/shell/$name and is ASCII', () {
        final file = File('../../term/shell/$name');
        expect(text, file.readAsStringSync());
        expect(text.codeUnits.every((c) => c < 0x80), isTrue);
        expect(text, startsWith('$blockStartMarker\n'));
        expect(text, endsWith('$blockEndMarker\n'));
      });
    }
  });

  group('insertBlock / removeBlock', () {
    test('puts the block at the top of the file', () {
      expect(
        insertBlock('export A=1\n', block, eol: '\n'),
        '${block}export A=1\n',
      );
      expect(insertBlock('', block, eol: '\n'), block);
    });

    test('inserting twice still leaves one block', () {
      final once = insertBlock('export A=1\n', block, eol: '\n');
      final twice = insertBlock(once, block, eol: '\n');
      expect(twice, once);
      expect(RegExp(blockStartMarker).allMatches(twice), hasLength(1));
    });

    test('an older block is replaced by the current one', () {
      final old = insertBlock(
        'x\n',
        '# >>> ShellX >>>\nold\n# <<< ShellX <<<\n',
        eol: '\n',
      );
      expect(insertBlock(old, block, eol: '\n'), '${block}x\n');
    });

    test('a block moved down the file is moved back to the top', () {
      const text =
          'a\n$block'
          'b\n';
      expect(insertBlock(text, block, eol: '\n'), '${block}a\nb\n');
    });

    test('remove is the exact inverse of insert', () {
      for (final text in ['', 'a', 'a\n', '\n\nb\r\n', 'no newline at end']) {
        expect(removeBlock(insertBlock(text, block, eol: '\n')), text);
      }
    });

    test('remove deletes only what is between the markers', () {
      const text =
          'before\n$block'
          'after\n';
      expect(removeBlock(text), 'before\nafter\n');
    });

    test('remove of a file without a block changes nothing', () {
      expect(removeBlock('a\nb\n'), 'a\nb\n');
    });

    test('a start marker without an end marker is left alone', () {
      const text = '# >>> ShellX >>>\necho half\n';
      expect(removeBlock(text), text);
      expect(hasBlock(text), isFalse);
    });

    test('a block whose last line has no newline is removed', () {
      const text = 'a\n# >>> ShellX >>>\nx\n# <<< ShellX <<<';
      expect(removeBlock(text), 'a\n');
    });

    test('CRLF: the block is written with the file\'s line ending', () {
      final result = insertBlock('a\r\nb\r\n', block, eol: '\r\n');
      expect(result, '${block.replaceAll('\n', '\r\n')}a\r\nb\r\n');
      expect(removeBlock(result), 'a\r\nb\r\n');
      expect(installedBlock(result), block);
    });

    test('installedBlock returns the block normalized to LF', () {
      expect(installedBlock('x\n'), isNull);
      expect(installedBlock(insertBlock('x\n', block, eol: '\n')), block);
    });
  });

  group('decode / encode', () {
    test('UTF-8 without BOM round-trips, including Vietnamese text', () {
      final bytes = Uint8List.fromList(
        utf8.encode('# Tiếng Việt\nexport A=1\n'),
      );
      final config = decodeConfig(bytes);
      expect(config.encoding, ConfigEncoding.ascii8);
      expect(config.eol, '\n');
      expect(encodeConfig(config), bytes);
      final edited = config.withText(
        insertBlock(config.text, block, eol: config.eol ?? '\n'),
      );
      final reread = decodeConfig(encodeConfig(edited));
      expect(
        utf8.decode(encodeConfig(reread.withText(removeBlock(reread.text)))),
        '# Tiếng Việt\nexport A=1\n',
      );
    });

    test('a legacy 8-bit code page (not UTF-8) is kept byte for byte', () {
      // Windows-1252 "café" (0xE9) is invalid UTF-8.
      final bytes = Uint8List.fromList([
        ...ascii.encode('# caf'),
        0xE9,
        0x0D,
        0x0A,
      ]);
      final config = decodeConfig(bytes);
      final edited = decodeConfig(
        encodeConfig(
          config.withText(insertBlock(config.text, block, eol: config.eol!)),
        ),
      );
      expect(encodeConfig(edited.withText(removeBlock(edited.text))), bytes);
      expect(config.eol, '\r\n');
    });

    test('UTF-8 with BOM keeps the BOM in front of the block', () {
      final bytes = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('Write-Host hi\r\n'),
      ]);
      final config = decodeConfig(bytes);
      expect(config.encoding, ConfigEncoding.utf8Bom);
      final out = encodeConfig(
        config.withText(insertBlock(config.text, block, eol: config.eol!)),
      );
      expect(out.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(out.sublist(3)), startsWith('# >>> ShellX >>>\r\n'));
    });

    for (final littleEndian in [true, false]) {
      final name = littleEndian ? 'LE' : 'BE';
      test('UTF-16 $name round-trips and stays UTF-16 $name', () {
        const text = 'Write-Host "Xin chào"\r\n';
        final bytes = utf16(text, littleEndian: littleEndian);
        final config = decodeConfig(bytes);
        expect(
          config.encoding,
          littleEndian ? ConfigEncoding.utf16le : ConfigEncoding.utf16be,
        );
        expect(config.text, text);
        expect(encodeConfig(config), bytes);
        final out = encodeConfig(
          config.withText(insertBlock(config.text, block, eol: config.eol!)),
        );
        expect(
          out,
          utf16(
            insertBlock(text, block, eol: '\r\n'),
            littleEndian: littleEndian,
          ),
        );
      });
    }

    test('UTF-16 with an odd number of bytes is refused', () {
      expect(
        () => decodeConfig(Uint8List.fromList([0xFF, 0xFE, 0x41])),
        throwsFormatException,
      );
    });

    test('no newline at all: line ending unknown', () {
      expect(decodeConfig(Uint8List.fromList(ascii.encode('x'))).eol, isNull);
      expect(decodeConfig(Uint8List(0)).eol, isNull);
    });
  });
}
