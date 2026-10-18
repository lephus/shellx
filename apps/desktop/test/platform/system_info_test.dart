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

  test('normalizes the OS version for the relay', () {
    expect(
      normalizedOsVersion('Version 14.5 (Build 23F79)', isMacOS: true),
      '14.5',
    );
    expect(
      normalizedOsVersion('Version 15.1.1 (Build 24B91)', isMacOS: true),
      '15.1.1',
    );
    expect(
      normalizedOsVersion('Version 12.7.6 (Build 21H1320)', isMacOS: true),
      '12.7.6',
    );
    expect(
      normalizedOsVersion(
        '"Windows 10 Pro" 10.0 (Build 22631)',
        isMacOS: false,
      ),
      '10.0.22631',
    );
    expect(normalizedOsVersion('garbage', isMacOS: true), isNull);
  });
}
