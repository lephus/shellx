import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_key_edits.dart';
import 'package:shellx_desktop/src/config/config_writer.dart';

void main() {
  test('removes only our block; the keybind block and user lines stay', () {
    const text =
        'theme = X\n# >>> shellx-managed keybinds >>>\nkeybind = a=b\n'
        '# <<< shellx-managed keybinds <<<\n$kSettingsStart\nfont-size = 15\n$kSettingsEnd\n';
    expect(
      removeSettingsBlock(text),
      'theme = X\n# >>> shellx-managed keybinds >>>\nkeybind = a=b\n# <<< shellx-managed keybinds <<<\n',
    );
  });

  test('no block: unchanged; damaged block: refused', () {
    expect(removeSettingsBlock('a = 1\n'), 'a = 1\n');
    expect(
      () => removeSettingsBlock('$kSettingsStart\nx\n'),
      throwsA(isA<ConfigWriteRefused>()),
    );
  });

  test(
    'CRLF, BOM-less text before and after the block is kept byte for byte',
    () {
      const text =
          '# mine\r\n$kSettingsStart\r\nfont-size = 15\r\n$kSettingsEnd\r\nlast = 1\r\n';
      expect(removeSettingsBlock(text), '# mine\r\nlast = 1\r\n');
    },
  );

  test('a block at the very end without a final newline', () {
    expect(
      removeSettingsBlock('a = 1\n$kSettingsStart\nx = 1\n$kSettingsEnd'),
      'a = 1\n',
    );
  });
}
