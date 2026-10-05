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

  test('terminal sharing texts (spec §9) in both languages', () async {
    final vi = await S.load(const Locale('vi'));
    expect(vi.pickerDesktopGroup, 'Terminal trên máy tính');
    expect(vi.pickerShellxGroup, 'Phiên ShellX');
    expect(vi.pickerNewSession, 'Phiên mới');
    expect(
      vi.pickerHintSharingOff,
      "Bật 'Chia sẻ terminal' trong menu ShellX trên máy tính để xem các terminal đang mở ở đây.",
    );
    expect(vi.pickerHintUpdateDesktop, 'Cập nhật ShellX trên máy tính để xem các terminal đang mở.');
    expect(
      vi.pickerHintOpenNewWindow,
      'Chỉ các cửa sổ terminal mở sau khi bật chia sẻ mới hiện ở đây. Mở một cửa sổ terminal mới trên máy tính.',
    );
    expect(vi.desktopStillRunning, 'Terminal vẫn chạy trên máy tính.');
    expect(vi.desktopDriverBanner, 'Máy tính đang dùng terminal này');
    expect(vi.desktopWindowClosed, 'Cửa sổ terminal trên máy tính đã đóng.');
    expect(vi.desktopTerminalGone, 'Mất kết nối với terminal này trên máy tính.');
    expect(vi.desktopClosedByHost, 'Máy tính đã ngắt điện thoại khỏi terminal này.');
    final en = await S.load(const Locale('en'));
    expect(en.pickerDesktopGroup, 'Terminals on the computer');
    expect(en.pickerShellxGroup, 'ShellX sessions');
    expect(en.pickerNewSession, 'New session');
    expect(
      en.pickerHintSharingOff,
      "Turn on 'Share terminal' in the ShellX menu on the computer to see its open terminals here.",
    );
    expect(en.pickerHintUpdateDesktop, 'Update ShellX on the computer to see its open terminals.');
    expect(
      en.pickerHintOpenNewWindow,
      'Only terminal windows opened after sharing was turned on show up here. '
      'Open a new terminal window on the computer.',
    );
    expect(en.desktopTerminalLabel, 'Terminal on the computer');
    expect(en.desktopStillRunning, 'The terminal is still running on the computer.');
    expect(en.desktopDriverBanner, 'The computer is using this terminal');
    expect(en.desktopWindowClosed, 'The terminal window on the computer was closed.');
    expect(en.desktopTerminalGone, 'Lost the connection to this terminal on the computer.');
    expect(en.desktopClosedByHost, 'The computer disconnected this phone from this terminal.');
    expect(vi.desktopTerminalLabel, 'Terminal trên máy tính');
  });

  testWidgets('S.of(context) resolves Vietnamese inside the design system', (tester) async {
    await tester.pumpWidget(localized(Builder(builder: (context) => Text(S.of(context).machinesTitle))));
    await tester.pumpAndSettle();
    expect(find.text('Máy của bạn'), findsOneWidget);
  });
}
