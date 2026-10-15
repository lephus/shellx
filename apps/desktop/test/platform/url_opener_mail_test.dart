import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';

void main() {
  late List<String> ran;
  Future<ProcessResult> run(String exe, List<String> args) async {
    ran.add(jsonEncode([exe, ...args]));
    return ProcessResult(0, 0, '', '');
  }

  setUp(() => ran = []);

  test('mailto: and tel: go to the system (V2-3 D9)', () async {
    await SystemUrlOpener(
      isWindows: false,
      run: run,
    ).openMailOrPhone(Uri.parse('mailto:a@b.c?subject=hi'));
    await SystemUrlOpener(
      isWindows: true,
      run: run,
    ).openMailOrPhone(Uri.parse('tel:+84123'));
    expect(ran, [
      '["/usr/bin/open","mailto:a@b.c?subject=hi"]',
      '["rundll32","url.dll,FileProtocolHandler","tel:+84123"]',
    ]);
  });

  test('nothing else ever reaches a command', () async {
    final opener = SystemUrlOpener(isWindows: false, run: run);
    for (final bad in [
      'https://example.com',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'sms:123',
      'facetime:x',
    ]) {
      await expectLater(
        opener.openMailOrPhone(Uri.parse(bad)),
        throwsArgumentError,
        reason: bad,
      );
    }
    expect(ran, isEmpty);
  });

  test('a link over 2 048 characters, or with a control character, is '
      'refused without a command', () async {
    final opener = SystemUrlOpener(isWindows: false, run: run);
    final longest = 'mailto:${'a' * (2048 - 'mailto:'.length)}';
    await opener.openMailOrPhone(Uri.parse(longest));
    expect(ran, ['["/usr/bin/open","$longest"]']);
    ran.clear();
    await expectLater(
      opener.openMailOrPhone(Uri.parse('${longest}a')),
      throwsArgumentError,
    );
    await expectLater(
      opener.openMailOrPhone(_RawUri('tel', 'tel:+84\n123')),
      throwsArgumentError,
    );
    expect(ran, isEmpty);
  });
}

/// A [Uri] that prints [text] as it is. A real one percent-encodes a
/// control character, so only this reaches the check for one.
final class _RawUri implements Uri {
  _RawUri(this.scheme, this.text);

  @override
  final String scheme;
  final String text;

  @override
  String toString() => text;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
