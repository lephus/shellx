import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/app/update_enforcer.dart';

import '../../support/fake_relay_http.dart';
import '../../support/fakes.dart';

/// The app's pages as stand-ins, the machine list first (the launch's first page).
class _Router extends RootStackRouter {
  static PageInfo _stub(String name) => PageInfo(name, builder: (_) => Scaffold(body: Text('$name stub')));

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: _stub(MachineListRoute.name), initial: true),
    AutoRoute(page: _stub(TerminalRoute.name)),
    AutoRoute(page: _stub(UpdateRequiredRoute.name)),
  ];
}

/// Force update (contract §5): the version check when the app returns to the foreground.
void main() {
  late FakeRelayHttp relay;
  late DateTime now;
  late VersionGate gate;
  late FakeSessionHolder session;
  late _Router router;

  setUp(() {
    relay = FakeRelayHttp();
    now = DateTime(2026, 10, 15, 9);
    gate = VersionGate(
      ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client),
      PackageInfo(appName: 'ShellX', packageName: 'com.shellx.prod', version: '1.0.0', buildNumber: '1'),
      now: () => now,
    );
    session = FakeSessionHolder(FakeBackend());
  });

  /// The launch: its version check, then the first page — "Cần cập nhật app" when the check
  /// blocks (what `UpdateGuard` does).
  Future<void> launch(WidgetTester tester) async {
    await gate.check();
    router = _Router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config()));
    await tester.pumpAndSettle();
    if (gate.requiredVersion.peek() != null) {
      unawaited(router.replaceAll([const UpdateRequiredRoute()]));
      await tester.pumpAndSettle();
    }
  }

  /// A return to the foreground after [away].
  Future<void> foreground(WidgetTester tester, Duration away) async {
    now = now.add(away);
    final done = UpdateEnforcer(gate: gate, router: router, session: session).onForeground();
    await tester.pumpAndSettle();
    await done;
  }

  List<String> stack() => [for (final page in router.stack) page.routeData.name];

  int versionRequests() => relay.requests.where((request) => request.url.path == '/v1/version').length;

  testWidgets('too old at a foreground 10 min after launch: every page gives way to the update page', (tester) async {
    await launch(tester);
    unawaited(router.push(TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro')));
    await tester.pumpAndSettle();
    expect(stack(), [MachineListRoute.name, TerminalRoute.name]);

    relay.minMobile = '2.0.0';
    await foreground(tester, VersionGate.recheckInterval);
    expect(stack(), [UpdateRequiredRoute.name]);
    expect(find.text('UpdateRequiredRoute stub'), findsOneWidget);
    expect(session.restoreCalls, 0);
  });

  testWidgets('a foreground within 10 min of the last check checks nothing', (tester) async {
    await launch(tester);
    relay.minMobile = '2.0.0';
    await foreground(tester, const Duration(minutes: 9));
    expect(versionRequests(), 1);
    expect(stack(), [MachineListRoute.name]);

    // 10 minutes after the launch's check.
    await foreground(tester, const Duration(minutes: 1));
    expect(versionRequests(), 2);
    expect(stack(), [UpdateRequiredRoute.name]);
  });

  testWidgets('a blocked launch let through later restores the saved session, then opens the first page', (
    tester,
  ) async {
    session = FakeSessionHolder();
    relay.minMobile = '2.0.0';
    await launch(tester);
    expect(stack(), [UpdateRequiredRoute.name]);

    // Still too old: it stays.
    await foreground(tester, VersionGate.recheckInterval);
    expect(stack(), [UpdateRequiredRoute.name]);

    relay.minMobile = '1.0.0';
    await foreground(tester, VersionGate.recheckInterval);
    expect(session.restoreCalls, 1);
    expect(stack(), [MachineListRoute.name]);
  });

  testWidgets('blocked at a foreground and let through at a later one: the session is kept, not restored again', (
    tester,
  ) async {
    await launch(tester);
    relay.minMobile = '2.0.0';
    await foreground(tester, VersionGate.recheckInterval);
    expect(stack(), [UpdateRequiredRoute.name]);

    relay.minMobile = '1.0.0';
    await foreground(tester, VersionGate.recheckInterval);
    expect(session.restoreCalls, 0);
    expect(stack(), [MachineListRoute.name]);
  });

  testWidgets('a session that cannot be restored still leaves the update page', (tester) async {
    session = FakeSessionHolder()..restoreError = PlatformException(code: 'keychain');
    relay.minMobile = '2.0.0';
    await launch(tester);

    relay.minMobile = '1.0.0';
    await foreground(tester, VersionGate.recheckInterval);
    expect(tester.takeException(), isNull);
    expect(session.restoreCalls, 1);
    expect(stack(), [MachineListRoute.name]);
  });

  testWidgets('offline, or a relay that never answers, changes nothing', (tester) async {
    await launch(tester);
    unawaited(router.push(TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro')));
    await tester.pumpAndSettle();
    relay
      ..minMobile = '2.0.0'
      ..versionOffline = true;
    await foreground(tester, VersionGate.recheckInterval);
    expect(versionRequests(), 2);
    expect(stack(), [MachineListRoute.name, TerminalRoute.name]);

    relay
      ..versionOffline = false
      ..versionGate = Completer<void>();
    now = now.add(VersionGate.recheckInterval);
    var done = false;
    unawaited(UpdateEnforcer(gate: gate, router: router, session: session).onForeground().then((_) => done = true));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(stack(), [MachineListRoute.name, TerminalRoute.name]);

    // The late answer is dropped (and ends the API's own request timer).
    relay.versionGate!.complete();
    await tester.pumpAndSettle();
    expect(gate.requiredVersion.value, isNull);
    expect(stack(), [MachineListRoute.name, TerminalRoute.name]);
  });

  testWidgets('a blocked app stays blocked while the relay cannot be reached', (tester) async {
    session = FakeSessionHolder();
    relay.minMobile = '2.0.0';
    await launch(tester);
    relay
      ..minMobile = '1.0.0'
      ..versionOffline = true;
    await foreground(tester, VersionGate.recheckInterval);
    expect(stack(), [UpdateRequiredRoute.name]);
    expect(session.restoreCalls, 0);
  });

  testWidgets('the update page a machine\'s proto_unsupported opened is left alone', (tester) async {
    await launch(tester);
    unawaited(router.push(const UpdateRequiredRoute()));
    await tester.pumpAndSettle();
    await foreground(tester, VersionGate.recheckInterval);
    expect(versionRequests(), 2);
    expect(stack(), [MachineListRoute.name, UpdateRequiredRoute.name]);
  });
}
