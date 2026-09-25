import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/l10n/locale.dart';

Map<String, Object?> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, Object?>;

void main() {
  test('Vietnamese when the system prefers it, English otherwise', () {
    expect(resolveAppLocale(const [Locale('vi', 'VN')]), const Locale('vi'));
    expect(
      resolveAppLocale(const [Locale('fr'), Locale('vi')]),
      const Locale('vi'),
    );
    expect(resolveAppLocale(const [Locale('en', 'US')]), const Locale('en'));
    expect(resolveAppLocale(const [Locale('ja')]), const Locale('en'));
    expect(resolveAppLocale(const []), const Locale('en'));
  });

  test('both ARB files define exactly the same non-empty messages', () {
    final en = _arb('app_en.arb');
    final vi = _arb('app_vi.arb');
    Set<String> keys(Map<String, Object?> arb) =>
        arb.keys.where((k) => !k.startsWith('@')).toSet();
    expect(keys(vi), keys(en));
    for (final key in keys(en)) {
      expect((en[key] as String).trim(), isNotEmpty, reason: 'en $key');
      expect((vi[key] as String).trim(), isNotEmpty, reason: 'vi $key');
    }
  });

  test('Vietnamese strings match the spec wording', () {
    final vi = lookupAppLocalizations(const Locale('vi'));
    expect(
      vi.trayStatusConnected('user@email.com'),
      'Đã kết nối — user@email.com',
    );
    expect(vi.trayRemoteAccess, 'Cho phép truy cập từ xa');
    expect(vi.traySessions(2), 'Phiên đang hoạt động (2)');
    expect(vi.traySessionClose, 'Đóng');
    expect(vi.trayCloseAll, 'Đóng tất cả');
    expect(vi.trayPairPhone, 'Ghép nối điện thoại…');
    expect(vi.trayPairedDevices, 'Thiết bị đã ghép');
    expect(vi.trayRevoke, 'Thu hồi');
    expect(vi.trayKeepAwake, 'Giữ máy không ngủ');
    expect(vi.trayLaunchAtStartup, 'Khởi động cùng hệ thống');
    expect(vi.trayChangePassword, 'Đổi mật khẩu…');
    expect(vi.traySignOut, 'Đăng xuất');
    expect(vi.trayQuit, 'Thoát');
    expect(vi.notifySessionOpened('iPhone'), 'iPhone vừa mở phiên terminal');
    expect(vi.notifyPaired('iPhone'), 'Đã ghép nối với iPhone');
    expect(vi.errorRateLimited, 'Thử lại sau ít phút.');
    expect(vi.notifyUpdateRequiredTitle, 'Cần cập nhật app');
  });

  test('plural and select messages render in both languages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final vi = lookupAppLocalizations(const Locale('vi'));
    expect(en.confirmRemoteOffBody(1), '1 open session will be closed.');
    expect(en.confirmRemoteOffBody(3), '3 open sessions will be closed.');
    expect(vi.confirmRemoteOffBody(3), '3 phiên đang mở sẽ bị đóng.');
    expect(en.onboardingTrayHint('macos'), contains('menu bar'));
    expect(en.onboardingTrayHint('windows'), contains('system tray'));
  });
}
