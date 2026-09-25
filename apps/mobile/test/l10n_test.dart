import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

import 'support/app_harness.dart';

Set<String> messageKeys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return json.keys.where((key) => !key.startsWith('@')).toSet();
}

void main() {
  test('Vietnamese and English ARB files define the same messages', () {
    expect(messageKeys('lib/l10n/intl_vi.arb'), messageKeys('lib/l10n/intl_en.arb'));
  });

  test('the generated strings are fresh: every ARB key has a getter in S', () {
    final generated = File('lib/shared/src/l10n.dart').readAsStringSync();
    for (final key in messageKeys('lib/l10n/intl_en.arb')) {
      expect(generated, contains("name: '$key'"), reason: key);
    }
  });

  test('exactly English and Vietnamese are supported', () {
    expect(S.delegate.supportedLocales.map((locale) => locale.languageCode), unorderedEquals(['en', 'vi']));
  });

  test('spec texts and plurals in both languages', () async {
    final vi = await S.load(const Locale('vi'));
    expect(vi.bannerReconnecting, 'Mất kết nối, đang thử lại…');
    expect(vi.lastSeenMinutes(5), '5 phút trước');
    final en = await S.load(const Locale('en'));
    expect(en.bannerReconnecting, 'Connection lost, retrying…');
    expect(en.lastSeenMinutes(1), '1 minute ago');
    expect(en.lastSeenMinutes(5), '5 minutes ago');
  });

  testWidgets('S.of(context) resolves Vietnamese inside the design system', (tester) async {
    await tester.pumpWidget(localized(Builder(builder: (context) => Text(S.of(context).machinesTitle))));
    await tester.pumpAndSettle();
    expect(find.text('Máy của bạn'), findsOneWidget);
  });
}
