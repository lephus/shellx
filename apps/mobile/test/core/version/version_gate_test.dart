import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

import '../../support/fake_relay_http.dart';

void main() {
  late FakeRelayHttp relay;

  VersionGate gate(String appVersion) => VersionGate(
    ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client),
    PackageInfo(appName: 'ShellX', packageName: 'com.shellx.prod', version: appVersion, buildNumber: '1'),
  );

  setUp(() => relay = FakeRelayHttp());

  test('blocks the app when older than min_mobile (spec §14)', () async {
    relay.minMobile = '1.2.0';
    final old = gate('1.1.9');
    await old.check();
    expect(old.requiredVersion.value, '1.2.0');

    final current = gate('1.2.0');
    await current.check();
    expect(current.requiredVersion.value, isNull);
  });

  test('an unreachable /v1/version does not block the app', () async {
    relay.versionOffline = true;
    final offline = gate('1.0.0');
    await offline.check();
    expect(offline.requiredVersion.value, isNull);
  });

  test('a /v1/version that never answers holds the launch for 5 s at most', () {
    fakeAsync((async) {
      relay.versionGate = Completer<void>();
      final hanging = gate('1.0.0');
      var done = false;
      unawaited(hanging.check().then((_) => done = true));

      async.elapse(const Duration(seconds: 5));
      expect(done, isTrue);
      expect(hanging.requiredVersion.value, isNull);
    });
  });

  test('a min_mobile that is not a version does not block the app', () async {
    relay.minMobile = 'soon';
    final gated = gate('1.0.0');
    await gated.check();
    expect(gated.requiredVersion.value, isNull);
  });
}
