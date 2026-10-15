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

  group('recheck (force update, contract §5)', () {
    late DateTime now;

    VersionGate clocked(String appVersion) => VersionGate(
      ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client),
      PackageInfo(appName: 'ShellX', packageName: 'com.shellx.prod', version: appVersion, buildNumber: '1'),
      now: () => now,
    );

    int versionRequests() => relay.requests.where((request) => request.url.path == '/v1/version').length;

    setUp(() => now = DateTime(2026, 10, 15, 9));

    test('runs at most once per 10 minutes, the launch check included', () async {
      final gated = clocked('1.0.0');
      await gated.check();
      relay.minMobile = '2.0.0';

      now = now.add(const Duration(minutes: 9, seconds: 59));
      expect(await gated.recheck(), isFalse);
      expect(gated.requiredVersion.value, isNull);
      expect(versionRequests(), 1);

      now = now.add(const Duration(seconds: 1));
      expect(await gated.recheck(), isTrue);
      expect(gated.requiredVersion.value, '2.0.0');
      expect(versionRequests(), 2);

      // The next one counts from this check.
      now = now.add(const Duration(minutes: 5));
      expect(await gated.recheck(), isFalse);
      expect(versionRequests(), 2);
    });

    test('a later check lets a blocked app through once min_mobile is lowered', () async {
      relay.minMobile = '2.0.0';
      final gated = clocked('1.0.0');
      await gated.check();
      expect(gated.requiredVersion.value, '2.0.0');

      relay.minMobile = '1.0.0';
      now = now.add(VersionGate.recheckInterval);
      expect(await gated.recheck(), isTrue);
      expect(gated.requiredVersion.value, isNull);
    });

    test('offline keeps the last answer: it never blocks, and never unblocks', () async {
      final open = clocked('1.0.0');
      await open.check();
      relay
        ..minMobile = '2.0.0'
        ..versionOffline = true;
      now = now.add(VersionGate.recheckInterval);
      expect(await open.recheck(), isTrue);
      expect(open.requiredVersion.value, isNull);

      relay.versionOffline = false;
      final blocked = clocked('1.0.0');
      await blocked.check();
      relay
        ..minMobile = '1.0.0'
        ..versionOffline = true;
      now = now.add(VersionGate.recheckInterval);
      expect(await blocked.recheck(), isTrue);
      expect(blocked.requiredVersion.value, '2.0.0');
    });

    test('a relay that never answers holds a foreground check for 5 s at most', () {
      fakeAsync((async) {
        final gated = clocked('1.0.0');
        relay.versionGate = Completer<void>();
        var ran = false;
        unawaited(gated.recheck().then((value) => ran = value));

        async.elapse(const Duration(seconds: 5));
        expect(ran, isTrue);
        expect(gated.requiredVersion.value, isNull);
      });
    });

    test('a check still running is not started again', () {
      fakeAsync((async) {
        final gated = clocked('1.0.0');
        relay.versionGate = Completer<void>();
        unawaited(gated.check());
        async.flushMicrotasks();

        bool? second;
        unawaited(gated.recheck().then((value) => second = value));
        async.flushMicrotasks();
        expect(second, isFalse);
        expect(versionRequests(), 1);
        async.elapse(const Duration(seconds: 5));
      });
    });

    test('a clock set back does not hold the checks off until it catches up', () async {
      final gated = clocked('1.0.0');
      await gated.check();
      relay.minMobile = '2.0.0';

      now = now.subtract(const Duration(hours: 1));
      expect(await gated.recheck(), isTrue);
      expect(gated.requiredVersion.value, '2.0.0');
    });
  });
}
