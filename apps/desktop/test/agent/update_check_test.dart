import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/update_check.dart';
import 'package:shellx_desktop/src/config.dart';

VersionInfo _info({
  String min = '1.0.0',
  String latest = '1.0.0',
  String? macUrl,
  String? winUrl,
}) => VersionInfo(
  minAgent: min,
  minMobile: '1.0.0',
  latestAgent: LatestAgent(
    version: latest,
    macUrl: Uri.parse(
      macUrl ??
          'https://download.shellx.pro/desktop/$latest/ShellX-$latest.dmg',
    ),
    winUrl: Uri.parse(
      winUrl ??
          'https://download.shellx.pro/desktop/$latest/ShellX-Setup-$latest.exe',
    ),
  ),
);

void main() {
  test('up to date → no notice', () {
    expect(
      evaluateUpdate(
        _info(),
        appVersion: '1.0.0',
        platform: DevicePlatform.macos,
      ),
      isNull,
    );
  });

  test('newer latest_agent → optional update with the platform URL', () {
    final mac = evaluateUpdate(
      _info(latest: '1.1.0'),
      appVersion: '1.0.0',
      platform: DevicePlatform.macos,
    )!;
    final win = evaluateUpdate(
      _info(latest: '1.1.0'),
      appVersion: '1.0.0',
      platform: DevicePlatform.windows,
    )!;
    expect(mac.required, isFalse);
    expect(mac.url.path, endsWith('ShellX-1.1.0.dmg'));
    expect(win.url.path, endsWith('ShellX-Setup-1.1.0.exe'));
  });

  test('below min_agent → required update', () {
    final notice = evaluateUpdate(
      _info(min: '1.2.0', latest: '1.2.0'),
      appVersion: '1.0.0',
      platform: DevicePlatform.macos,
    )!;
    expect(notice.required, isTrue);
    expect(notice.version, '1.2.0');
  });

  test('an unparsable server version is ignored instead of crashing', () {
    expect(
      evaluateUpdate(
        _info(latest: 'soon'),
        appVersion: '1.0.0',
        platform: DevicePlatform.macos,
      ),
      isNull,
    );
  });

  test('x.y.z-looking versions compareVersions refuses are ignored too', () {
    // A leading zero or an out-of-range number looks like x.y.z but is not
    // semver: compareVersions throws FormatException for both.
    for (final bad in ['01.2.0', '1.99999999999999999999.0']) {
      expect(
        evaluateUpdate(
          _info(latest: bad),
          appVersion: '1.0.0',
          platform: DevicePlatform.macos,
        ),
        isNull,
        reason: bad,
      );
      expect(
        evaluateUpdate(
          _info(min: bad),
          appVersion: '1.0.0',
          platform: DevicePlatform.macos,
        ),
        isNull,
        reason: bad,
      );
    }
  });

  group('the download link must be https on shellx.pro (the relay can only '
      'reduce trust)', () {
    const rejected = <String>[
      'file:///Applications/Calculator.app',
      'file://evil-host/share/ShellX.exe',
      r'\\evil-host\share\ShellX.exe',
      '/desktop/ShellX-1.1.0.dmg',
      'download.shellx.pro/desktop/ShellX-1.1.0.dmg',
      '-aCalculator',
      'http://download.shellx.pro/desktop/ShellX-1.1.0.dmg',
      'https://evil.example/ShellX-1.1.0.dmg',
      'https://shellx.pro.evil.example/ShellX-1.1.0.dmg',
      'https://evilshellx.pro/ShellX-1.1.0.dmg',
      'https://shellx.pro@evil.example/ShellX-1.1.0.dmg',
      'https://user@download.shellx.pro/ShellX-1.1.0.dmg',
      'smb://download.shellx.pro/ShellX-1.1.0.dmg',
      'x-apple.systempreferences:com.apple.preference.security',
    ];
    for (final url in rejected) {
      test('rejected: $url', () {
        for (final platform in DevicePlatform.values) {
          final info = _info(latest: '1.1.0', macUrl: url, winUrl: url);
          expect(
            evaluateUpdate(info, appVersion: '1.0.0', platform: platform),
            isNull,
            reason: '$platform',
          );
          final required = _info(
            min: '1.1.0',
            latest: '1.1.0',
            macUrl: url,
            winUrl: url,
          );
          expect(
            evaluateUpdate(required, appVersion: '1.0.0', platform: platform),
            isNull,
            reason: '$platform, required',
          );
        }
      });
    }

    for (final url in [
      'https://download.shellx.pro/desktop/1.1.0/ShellX-1.1.0.dmg',
      'https://shellx.pro/download',
      'https://DOWNLOAD.ShellX.pro/x.dmg',
    ]) {
      test('accepted: $url', () {
        final notice = evaluateUpdate(
          _info(latest: '1.1.0', macUrl: url),
          appVersion: '1.0.0',
          platform: DevicePlatform.macos,
        );
        expect(notice, isNotNull);
        expect(notice!.url, Uri.parse(url));
      });
    }

    test('only the platform\'s own link counts', () {
      final info = _info(
        latest: '1.1.0',
        macUrl: 'https://download.shellx.pro/ShellX-1.1.0.dmg',
        winUrl: 'file:///C:/Windows/System32/calc.exe',
      );
      expect(
        evaluateUpdate(
          info,
          appVersion: '1.0.0',
          platform: DevicePlatform.macos,
        ),
        isNotNull,
      );
      expect(
        evaluateUpdate(
          info,
          appVersion: '1.0.0',
          platform: DevicePlatform.windows,
        ),
        isNull,
      );
    });
  });

  test('relay WebSocket URI follows the base URL scheme', () {
    expect(
      relayWebSocketUri(Uri.parse('https://relay.shellx.pro')).toString(),
      'wss://relay.shellx.pro/v1/ws',
    );
    expect(
      relayWebSocketUri(Uri.parse('http://127.0.0.1:8787')).toString(),
      'ws://127.0.0.1:8787/v1/ws',
    );
  });
}
