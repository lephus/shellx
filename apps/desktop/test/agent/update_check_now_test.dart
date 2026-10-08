import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/agent/update_check.dart';

import '../support/fakes.dart';

Map<String, Object?> info({
  String latest = '1.0.0',
  String min = '1.0.0',
  String mac = 'https://download.shellx.pro/desktop/a.dmg',
}) => {
  'min_agent': min,
  'min_mobile': '1.0.0',
  'latest_agent': {
    'version': latest,
    'mac_url': mac,
    'win_url': 'https://download.shellx.pro/desktop/a.exe',
  },
};

void main() {
  late TestHarness h;
  late ProviderContainer container;

  AgentController controller() =>
      container.read(agentControllerProvider.notifier) as AgentController;

  void boot({String appVersion = '1.0.0'}) {
    h = TestHarness(appVersion: appVersion);
    container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
  }

  group('checkForUpdateNow', () {
    test('up to date: says which version', () async {
      boot();
      h.relay.version = {...h.relay.version, ...info()};
      final r = await controller().checkForUpdateNow();
      expect(r, isA<UpToDate>());
      expect((r as UpToDate).version, '1.0.0');
      expect(h.notifier.shown, isEmpty);
    });

    test('a newer version is available, with its download page', () async {
      boot();
      h.relay.version = {...h.relay.version, ...info(latest: '1.2.0')};
      final r = await controller().checkForUpdateNow();
      final notice = (r as Available).notice;
      expect(notice.version, '1.2.0');
      expect(notice.required, isFalse);
      expect(notice.url.scheme, 'https');
      // No system notification: the answer is shown in place.
      expect(h.notifier.shown, isEmpty);
      // The tray's download item follows.
      expect(container.read(agentControllerProvider).update!.version, '1.2.0');
    });

    test('min_agent above this build: available and required', () async {
      boot(appVersion: '0.9.0');
      final r = await controller().checkForUpdateNow();
      final notice = (r as Available).notice;
      expect(notice.required, isTrue);
      expect(h.notifier.shown, isEmpty);
    });

    test('a download link the app does not trust is a failure', () async {
      boot();
      h.relay.version = {
        ...h.relay.version,
        ...info(latest: '1.2.0', mac: 'https://evil.example/a.dmg'),
      };
      expect(await controller().checkForUpdateNow(), isA<Failed>());
      h.relay.version = {
        ...h.relay.version,
        ...info(latest: '1.2.0', mac: 'http://download.shellx.pro/a.dmg'),
      };
      expect(await controller().checkForUpdateNow(), isA<Failed>());
    });

    test('a version that is not x.y.z is a failure, not a crash', () async {
      boot();
      h.relay.version = {...h.relay.version, ...info(latest: 'banana')};
      expect(await controller().checkForUpdateNow(), isA<Failed>());
    });

    test('offline: Failed, never throws', () async {
      boot();
      h.relay.offline = true;
      expect(await controller().checkForUpdateNow(), isA<Failed>());
    });

    test('a failed check keeps what the tray already knew', () async {
      boot();
      h.relay.version = {...h.relay.version, ...info(latest: '1.2.0')};
      await controller().checkForUpdateNow();
      h.relay.offline = true;
      await controller().checkForUpdateNow();
      expect(container.read(agentControllerProvider).update!.version, '1.2.0');
    });

    test('the result says nothing but its fields', () {
      expect(const Failed().toString(), isNot(contains('http')));
      expect(const UpToDate('1.0.0').version, '1.0.0');
    });
  });

  group('runUpdateCheck', () {
    VersionInfo versionInfo({String latest = '1.0.0'}) => VersionInfo(
      minAgent: '1.0.0',
      minMobile: '1.0.0',
      latestAgent: LatestAgent(
        version: latest,
        macUrl: Uri.parse('https://download.shellx.pro/desktop/a.dmg'),
        winUrl: Uri.parse('https://download.shellx.pro/desktop/a.exe'),
      ),
    );

    test('a relay that never answers fails after the timeout', () {
      fakeAsync((fa) {
        UpdateCheckResult? result;
        unawaited(
          runUpdateCheck(
            () => Completer<VersionInfo>().future,
            appVersion: '1.0.0',
            platform: DevicePlatform.macos,
          ).then((r) => result = r),
        );
        fa.elapse(const Duration(seconds: 9));
        expect(result, isNull);
        fa.elapse(const Duration(seconds: 2));
        expect(result, isA<Failed>());
      });
    });

    test('Windows reads the Windows link', () async {
      final r = await runUpdateCheck(
        () async => versionInfo(latest: '1.2.0'),
        appVersion: '1.0.0',
        platform: DevicePlatform.windows,
      );
      expect((r as Available).notice.url.path, endsWith('.exe'));
    });
  });

  group('wire', () {
    test('round trips the three outcomes', () {
      final a = Available(
        UpdateNotice(
          version: '1.2.0',
          url: Uri.parse('https://download.shellx.pro/a.dmg'),
          required: true,
        ),
      );
      for (final r in <UpdateCheckResult>[
        const UpToDate('1.0.0'),
        a,
        const Failed(),
      ]) {
        final back = updateCheckFromWire(updateCheckToWire(r));
        expect(back.runtimeType, r.runtimeType);
      }
      final back = updateCheckFromWire(updateCheckToWire(a)) as Available;
      expect(back.notice.version, '1.2.0');
      expect(back.notice.required, isTrue);
      expect(back.notice.url, a.notice.url);
    });

    test('what the other side sends is checked again', () {
      for (final bad in <Object?>[
        null,
        'x',
        <String, Object?>{},
        {'r': 'available', 'version': '1', 'url': 'https://shellx.pro/a'},
        {
          'r': 'available',
          'version': '1.2.0',
          'url': 'https://evil.example/a',
          'required': false,
        },
        {
          'r': 'available',
          'version': '1.2.0',
          'url': 'file:///etc/passwd',
          'required': false,
        },
        {'r': 'upToDate', 'version': 5},
        {'r': 'upToDate', 'version': 'banana'},
        {'r': 'weird'},
      ]) {
        expect(updateCheckFromWire(bad), isA<Failed>(), reason: '$bad');
      }
    });
  });
}
