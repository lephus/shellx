import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/config/config_problems_panel.dart';

void main() {
  test('the home prefix needs a separator boundary', () {
    expect(
      homeRelative('/home/me/.config/shellx/config', '/home/me'),
      '~/.config/shellx/config',
    );
    expect(homeRelative('/home/meow/config', '/home/me'), '/home/meow/config');
    expect(homeRelative('/home/me', '/home/me'), '~');
    expect(homeRelative(r'C:\Users\me\x', r'C:\Users\me'), r'~\x');
    expect(homeRelative('/x', ''), '/x');
  });

  test('a long path is cut in the middle', () {
    expect(middleEllipsis('short'), 'short');
    final cut = middleEllipsis('/a' * 60, max: 20);
    expect(cut.length, 20);
    expect(cut.contains('…'), isTrue);
    expect(cut.startsWith('/a/a'), isTrue);
    expect(cut.endsWith('/a'), isTrue);
  });
}
