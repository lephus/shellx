import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/system_info.dart';

void main() {
  test('parses the Windows build and enforces 1809 (17763)', () {
    expect(windowsBuildNumber('"Windows 10 Pro" 10.0 (Build 19045)'), 19045);
    expect(
      isSupportedWindowsBuild('"Windows 10 Pro" 10.0 (Build 17763)'),
      isTrue,
    );
    expect(
      isSupportedWindowsBuild('"Windows 10 Pro" 10.0 (Build 17134)'),
      isFalse,
    );
    expect(isSupportedWindowsBuild('something else'), isTrue);
  });

  test('device name drops .local and is never empty', () {
    expect(
      deviceNameFromHostname('Phus-MacBook-Pro.local'),
      'Phus-MacBook-Pro',
    );
    expect(deviceNameFromHostname('DESKTOP-7K2Q'), 'DESKTOP-7K2Q');
    expect(deviceNameFromHostname('  '), 'Computer');
    expect(deviceNameFromHostname('a' * 80), hasLength(64));
  });
}
